## Exercise `Http.start!` and `Http.PendingResponse` against
## ci/rust_http_server: a request in flight while others are sent, waits with
## and without a limit, redirects under one deadline, closing, and failures. The deadline
## and timing checks run in their own mode, as valgrind slows them.
## scripts/test.py checks that no handle is left open in any mode.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "../platform/main.roc",
}

import pf.Duration
import pf.Http
import pf.Monotonic
import pf.OsStr
import pf.Sleep
import pf.Stdout
import http.Request

check : Bool, Str -> Try({}, [CheckFailed(Str)])
check = |condition, message| if (condition) Ok({}) else Err(CheckFailed(message))

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"in-flight" => in_flight!()
		"redirects" => redirects!()
		"timing" => timing!()
		"close-and-errors" => close_and_errors!(args.len())
		_ => Err(UnknownMode(mode))
	}
}

request : Str -> Request
request = |path| Request.from_method(GET).with_uri("http://127.0.0.1:9000${path}")

text : List(U8) -> Str
text = |bytes| Str.from_utf8_lossy(bytes)

## Whether a wait found the response.
is_ready : Try([Ready(Http.StreamingResponse), NotReady], _) -> Bool
is_ready = |result|
	match result {
		Ok(Ready(_)) => True
		_ => False
	}

## Wait for the final response, then read its body.
wait_to_end! : Http.PendingResponse => Try(List(U8), _)
wait_to_end! = |pending| Ok(pending.wait!()?.read_to_end!(NoLimit)?)

## Wait in small steps until the final response has arrived, then read its body.
wait_in_steps_to_end! : Http.PendingResponse => Try(List(U8), _)
wait_in_steps_to_end! = |pending| {
	match pending.wait_within!(Duration.millis(100))? {
		Ready(response) => Ok(response.read_to_end!(NoLimit)?)
		NotReady => wait_in_steps_to_end!(pending)
	}
}

## What the app can do while a request is in flight, and what it gets back.
in_flight! : () => Try({}, _)
in_flight! = || {
	# "Not ready yet" is an answer, not a failure, and the request goes on.
	slow = Http.start!(request("/delay/1000"), {})?
	var $waits = 0
	var $answer = ""
	while $answer == "" {
		match slow.wait_within!(Duration.millis(100))? {
			Ready(response) => {
				$answer = text(response.read_to_end!(NoLimit)?)
			}
			NotReady => {
				$waits = $waits + 1
				# Other requests are served while the first one is in flight.
				if $waits == 1 {
					greeting = Http.get_utf8!("http://127.0.0.1:9000/utf8test", {})?
					check(greeting == "Hello utf8", "a request while another is pending")?
					second = Http.start!(request("/utf8test"), {})?
					second_response = second.wait!()?
					check(second_response.status() == 200 and text(second_response.read_to_end!(NoLimit)?) == "Hello utf8", "a second pending request")?
				}
			}
		}
	}
	check($waits >= 1, "the response was not ready at first")?
	check($answer == "waited 1000 ms", "the response of the pending request")?
	Stdout.line!("waiting while other requests are sent: ok")?

	# After the response has arrived, a wait returns it again: the same
	# body, read from one cursor.
	pending = Http.start!(request("/stream/sized"), {})?
	response = pending.wait!()?
	first = match Stream.next!(response.chunks()) {
		One({ item: Ok(chunk), .. }) => chunk
		_ => {
			return Err(ExpectedAChunk)
		}
	}
	again = pending.wait!()?
	check(again.status() == 200 and again.content_length() == Known(200_000), "the response again")?
	rest = again.read_to_end!(NoLimit)?
	check(first.len() + rest.len() == 200_000 and rest.len() > 0, "one body cursor")?
	check(is_ready(pending.wait_within!(Duration.zero)), "a zero wait finds the response")?
	Stdout.line!("the response is returned again: ok")?

	# A wait that does not wait returns a response that has arrived, although
	# the app made no HTTP call since the request was started. Several times,
	# as the host must turn its runtime more than once to read it.
	for _ in [1, 2, 3] {
		arrived = Http.start!(request("/utf8test"), {})?
		Sleep.millis!(300)?
		check(is_ready(arrived.wait_within!(Duration.zero)), "a zero wait finds a response that has arrived")?
	}
	Stdout.line!("a zero wait returns what has arrived: ok")
}

## Redirects behave as in `Http.send_streaming!`, hop by hop across waits.
redirects! : () => Try({}, _)
redirects! = || {
	chain = Http.start!(request("/redirect/chain/2"), { max_redirects: 2 })?
	check(text(chain.wait!()?.read_to_end!(NoLimit)?) == "final", "exact redirect budget")?
	unfollowed = Http.start!(request("/redirect/chain/2"), {})?
	check(unfollowed.wait!()?.status() == 302, "redirects are opt-in")?
	Stdout.line!("following redirects: ok")?

	looped = Http.start!(request("/redirect/loop"), { max_redirects: 2 })?
	for _ in [1, 2] {
		result = looped.wait!().map_ok(|response| response.status())
		check(result == Err(HttpErr(RedirectLimitExceeded(2))), "redirect budget enforced, every time")?
	}
	Stdout.line!("the redirect limit: ok")?

	cross = request("/redirect/302/cross").add_header("Authorization", "secret")
	report = text(Http.start!(cross, { max_redirects: 1 })?.wait!()?.read_to_end!(NoLimit)?)
	check(report.contains("authorization: <absent>\n") and report.contains("host: localhost:9000\n"), "credentials are not sent to another origin")?
	Stdout.line!("security checks: ok")?

	# One deadline covers every hop and the body, however the waits are cut up.
	for path in ["/redirect/delayed/1", "/redirect/delayed/2"] {
		timed = request(path).with_timeout(TimeoutMilliseconds(650))
		waited = Http.start!(timed, { max_redirects: 2 })?
		check(wait_to_end!(waited) == Err(HttpErr(Timeout)), "one deadline with wait!")?
		stepped = Http.start!(timed, { max_redirects: 2 })?
		check(wait_in_steps_to_end!(stepped) == Err(HttpErr(Timeout)), "one deadline with wait_within!")?
	}
	# Without a deadline the hops simply take their time.
	patient = Http.start!(request("/redirect/delayed/2"), { max_redirects: 2 })?
	check(text(wait_in_steps_to_end!(patient)?) == "final", "redirects followed across waits")?
	Stdout.line!("redirects across waits and one deadline: ok")
}

## Times: that `start!` does not wait, that the `Request` timeout counts
## from `start!`, and that a response that arrived in time is kept.
timing! : () => Try({}, _)
timing! = || {
	began = Monotonic.now!()
	pending = Http.start!(request("/delay/1000"), {})?
	check(began.elapsed!() < Duration.millis(500), "start! does not wait for the response")?
	check(is_ready(pending.wait_within!(Duration.millis(100))) == False, "wait_within! returned a response too early")?
	Stdout.line!("start! returns at once: ok")?

	# The timeout of the request counts from `start!`, also while the app is
	# not waiting for it. The late wait finds that it has expired.
	late = Http.start!(request("/delay/1000").with_timeout(TimeoutMilliseconds(300)), {})?
	Sleep.millis!(600)?
	check(late.wait_within!(Duration.zero).map_ok(|_| {}) == Err(HttpErr(Timeout)), "the timeout counts from start!")?
	check(late.wait!().map_ok(|_| {}) == Err(HttpErr(Timeout)), "a timeout is final")?
	waited = Monotonic.now!()
	early = Http.start!(request("/delay/1000").with_timeout(TimeoutMilliseconds(300)), {})?
	check(early.wait!().map_ok(|_| {}) == Err(HttpErr(Timeout)), "the timeout ends an unbounded wait")?
	check(waited.elapsed!() < Duration.millis(900), "the timeout ended the wait at 300 ms")?
	Stdout.line!("the timeout counts from start!: ok")?

	# A response that arrived in time, here during another request, is not
	# lost to a wait that comes only after its idle timeout.
	arrived = Http.start!(request("/utf8test"), { idle_timeout: After(Duration.millis(300)) })?
	other = Http.get_utf8!("http://127.0.0.1:9000/delay/100", {})?
	check(other == "waited 100 ms", "another request")?
	Sleep.millis!(600)?
	check(arrived.wait!()?.status() == 200, "a response that arrived in time")?
	Stdout.line!("a response that arrived in time is kept: ok")
}

## Closing cancels, and failures come back from the waits.
close_and_errors! : U64 => Try({}, _)
close_and_errors! = |arg_count| {
	# A second error beside the platform's, so each call below must widen.
	if arg_count > 1 {
		return Err(UnexpectedArguments)
	}
	closed = Http.start!(request("/delay/1000"), {})?
	closed.close!()
	closed.close!()
	check(closed.wait_within!(Duration.zero).map_ok(|_| {}) == Err(Closed), "wait_within! after close!")?
	check(closed.wait!().map_ok(|_| {}) == Err(Closed), "wait! after close!")?
	Stdout.line!("close! cancels: ok")?

	# Nothing listens on port 9: the failure is a transport error with a message.
	refused = Http.start!(Request.from_method(GET).with_uri("http://127.0.0.1:9/"), {})?
	for _ in [1, 2] {
		match refused.wait!() {
			Err(HttpErr(Other(message))) => check(!(message.is_empty()), "the error has a message")?
			_ => {
				return Err(CheckFailed("a refused connection"))
			}
		}
	}
	bad_url = Http.start!(Request.from_method(GET).with_uri("ftp://example.com/"), {}).map_ok(|_| {})
	check(bad_url == Err(InvalidUrl(UnsupportedScheme("ftp"))), "an invalid URL")?
	Stdout.line!("failures come back from the waits: ok")?

	# Functions as values beside another error: the rows have to widen.
	start! = Http.start!
	wait_within! = Http.PendingResponse.wait_within!
	wait! = Http.PendingResponse.wait!
	close! = Http.PendingResponse.close!
	pending = start!(request("/utf8test"), {})?
	waited_within = wait_within!(pending, Duration.seconds(10))?
	check(is_ready(Ok(waited_within)), "wait_within! as a function value")?
	check(wait!(pending)?.status() == 200, "wait! as a function value")?
	close!(pending)
	Stdout.line!("error rows: ok")
}
