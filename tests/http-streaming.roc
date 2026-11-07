## Exercise `Http.send_streaming!` against ci/rust_http_server: the head before
## the body, chunk sizes, `read_to_end!` and its limit, both timeouts, failures
## that end a body, and downloads through `File.Writer.write_stream!`.
## scripts/test.py checks that no response handle is left open in any mode.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "../platform/main.roc",
}

import pf.Duration
import pf.File
import pf.Http
import pf.OsStr
import pf.Path
import pf.Stdout
import http.Request

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"head" => head!()
		"chunks" => chunks!()
		"read-to-end" => read_to_end!()
		"idle-timeout" => idle_timeout!()
		"zero-timeouts" => zero_timeouts!()
		"deadline" => deadline!()
		"broken-body" => broken_body!()
		"download" => download!()
		"error-rows" => error_rows!(args.len())
		_ => Err(UnknownMode(mode))
	}
}

get : Str -> Request
get = |path| Request.from_method(GET).with_uri("http://127.0.0.1:9000${path}")

## The sum of the bytes, which together with the length identifies the
## server's test pattern.
checksum : List(U8) -> U64
checksum = |bytes| bytes.fold(0.U64, |sum, byte| sum + byte.to_u64())

expect checksum([]) == 0
expect checksum([1, 2, 250]) == 253

text : List(U8) -> Str
text = |bytes| Str.inspect(Str.from_utf8_lossy(bytes))

## The status, headers and declared length are there before the body is read,
## and a body that is not wanted is never read.
head! : () => Try({}, _)
head! = || {
	missing = Http.send_streaming!(get("/not-found"), {})?
	Stdout.line!("status: ${missing.status().to_str()}")?
	content_type = missing.headers().find_first(|header| header.name == "content-type").map_ok(|header| header.value)
	Stdout.line!("content-type: ${Str.inspect(content_type)}")?
	Stdout.line!("content_length: ${Str.inspect(missing.content_length())}")?
	Stdout.line!("inspect starts: ${Str.inspect(Str.inspect(missing).starts_with("Http.StreamingResponse({ status: 404, headers: ["))}")?
	Stdout.line!("inspect hides the handle: ${Str.inspect(!(Str.inspect(missing).contains("host")))}")?
	# Declined: `missing` is released with its body unread.

	# Any status is `Ok`, and its body is there for a caller who wants it.
	wanted = Http.send_streaming!(get("/not-found"), {})?
	Stdout.line!("404 body: ${text(wanted.read_to_end!(NoLimit)?)}")?

	sized = Http.send_streaming!(get("/stream/sized"), {})?
	Stdout.line!("sized: ${sized.status().to_str()}, ${Str.inspect(sized.content_length())}")?
	chunked = Http.send_streaming!(get("/stream/chunked"), {})?
	Stdout.line!("chunked: ${chunked.status().to_str()}, ${Str.inspect(chunked.content_length())}")
}

Tally : { count : U64, bytes : U64, sum : U64, empty : U64, largest : U64 }

tally! : Stream(Try(List(U8), [Interrupted, HttpErr(Http.TransportErr)])) => Try(Tally, [Interrupted, HttpErr(Http.TransportErr)])
tally! = |stream| {
	var $tally = { count: 0, bytes: 0, sum: 0, empty: 0, largest: 0 }
	for! item in stream {
		chunk = item?
		$tally = {
			count: $tally.count + 1,
			bytes: $tally.bytes + chunk.len(),
			sum: $tally.sum + checksum(chunk),
			empty: $tally.empty + (if (chunk.is_empty()) 1 else 0),
			largest: $tally.largest.max(chunk.len()),
		}
	}
	Ok($tally)
}

## Chunks are non-empty, at most 64 KiB, and add up to the body.
chunks! : () => Try({}, _)
chunks! = || {
	for path in ["/stream/sized", "/stream/chunked"] {
		response = Http.send_streaming!(get(path), { idle_timeout: After(Duration.seconds(5)) })?
		stream = response.chunks()
		tally = tally!(stream)?
		Stdout.line!("${path}: ${tally.bytes.to_str()} bytes, checksum ${tally.sum.to_str()}")?
		Stdout.line!("  more than one chunk: ${Str.inspect(tally.count > 1)}, empty chunks: ${tally.empty.to_str()}, largest within 64 KiB: ${Str.inspect(tally.largest <= 65_536)}")?

		# The end of the body is the end of every later stream and read.
		again = tally!(response.chunks())?
		Stdout.line!("  chunks after the end: ${again.count.to_str()}, read_to_end! after the end: ${Str.inspect(response.read_to_end!(NoLimit))}")?
	}

	# A stream keeps the response alive, and an unfinished one releases it.
	kept = Http.send_streaming!(get("/stream/chunked"), {})?.chunks()
	match Stream.next!(kept) {
		One({ item: Ok(first), .. }) => Stdout.line!("first chunk of a dropped stream is within 64 KiB: ${Str.inspect(first.len() > 0 and first.len() <= 65_536)}")
		_ => Err(ExpectedAChunk)
	}
}

## `read_to_end!` returns the unread remainder, shares the cursor with
## `chunks`, and stops at its limit without consuming anything.
read_to_end! : () => Try({}, _)
read_to_end! = || {
	response = Http.send_streaming!(get("/stream/sized"), {})?

	limited = response.read_to_end!(MaxBytes(1000))
	expect limited == Err(ReadLimitExceeded(1000))
	Stdout.line!("MaxBytes(1000): ${Str.inspect(limited.map_ok(List.len))}")?
	just_short = response.read_to_end!(MaxBytes(199_999))
	Stdout.line!("MaxBytes(199_999): ${Str.inspect(just_short.map_ok(List.len))}")?

	# Nothing was lost to the limit: a chunk, then the rest through a copy.
	first = match Stream.next!(response.chunks()) {
		One({ item: Ok(chunk), .. }) => chunk
		_ => {
			return Err(ExpectedAChunk)
		}
	}
	copy = response
	rest = copy.read_to_end!(MaxBytes(200_000 - first.len()))?
	Stdout.line!("a chunk and the remainder: ${(first.len() + rest.len()).to_str()} bytes, checksum ${(checksum(first) + checksum(rest)).to_str()}")?
	Stdout.line!("the remainder is the larger part: ${Str.inspect(rest.len() > first.len())}")?
	Stdout.line!("after the end: ${Str.inspect(response.read_to_end!(MaxBytes(0)))}")?

	exact = Http.send_streaming!(get("/stream/chunked"), {})?.read_to_end!(MaxBytes(300_000))?
	Stdout.line!("MaxBytes(300_000) of 300,000: ${exact.len().to_str()} bytes, checksum ${checksum(exact).to_str()}")?
	whole = Http.send_streaming!(get("/stream/chunked"), {})?.read_to_end!(NoLimit)?
	Stdout.line!("NoLimit: ${whole.len().to_str()} bytes, equal: ${Str.inspect(whole == exact)}")
}

## An idle timeout ends a stream but not the response: a new stream continues
## where the last one stopped.
idle_timeout! : () => Try({}, _)
idle_timeout! = || {
	# The server sends "one,", is silent for a second, then sends "two". The
	# idle timeout also bounds the wait for the status and headers, so it is
	# short enough to expire in that second and no shorter: the first request
	# of a process is the slowest, more so under Valgrind.
	response = Http.send_streaming!(get("/stream/slow"), { idle_timeout: After(Duration.millis(500)) })?
	var $body = []
	var $timeouts = 0.U64
	var $ended = False
	var $streams = 0.U64
	while !$ended and $streams < 100 {
		$streams = $streams + 1
		var $timed_out = False
		for! item in response.chunks() {
			match item {
				Ok(chunk) => {
					$body = $body.concat(chunk)
				}
				Err(HttpErr(Timeout)) => {
					$timed_out = True
				}
				Err(Interrupted) => {
					return Err(Interrupted)
				}
				Err(HttpErr(err)) => {
					return Err(HttpErr(err))
				}
			}
		}
		if $timed_out {
			$timeouts = $timeouts + 1
		} else {
			$ended = True
		}
	}
	Stdout.line!("body across the idle timeouts: ${text($body)}")?
	Stdout.line!("timed out at least once: ${Str.inspect($timeouts >= 1)}, then ended: ${Str.inspect($ended)}")?

	# `read_to_end!` keeps what it has collected when it times out.
	again = Http.send_streaming!(get("/stream/slow"), { idle_timeout: After(Duration.millis(500)) })?
	var $result = again.read_to_end!(NoLimit)
	var $read_timeouts = 0.U64
	while $result == Err(HttpErr(Timeout)) and $read_timeouts < 100 {
		$read_timeouts = $read_timeouts + 1
		$result = again.read_to_end!(NoLimit)
	}
	Stdout.line!("read_to_end! across the idle timeouts: ${Str.inspect($result.map_ok(Str.from_utf8_lossy))}, timed out at least once: ${Str.inspect($read_timeouts >= 1)}")?

	# A long enough idle timeout never fires.
	patient = Http.send_streaming!(get("/stream/slow"), { idle_timeout: After(Duration.seconds(10)) })?
	Stdout.line!("with a ten second idle timeout: ${text(patient.read_to_end!(NoLimit)?)}")
}

## `After(Duration.zero)` expires at once; a zero `Request` timeout is no
## deadline at all.
zero_timeouts! : () => Try({}, _)
zero_timeouts! = || {
	immediate = Http.send_streaming!(get("/stream/sized"), { idle_timeout: After(Duration.zero) }).map_ok(|response| response.status())
	expect immediate == Err(HttpErr(Timeout))
	Stdout.line!("After(Duration.zero): ${Str.inspect(immediate)}")?

	# No deadline and no idle timeout: the slow body arrives in its own time.
	no_deadline = get("/stream/slow").with_timeout(TimeoutMilliseconds(0))
	unhurried = Http.send_streaming!(no_deadline, { idle_timeout: NoTimeout })?
	Stdout.line!("TimeoutMilliseconds(0) and NoTimeout: ${text(unhurried.read_to_end!(NoLimit)?)}")?
	default = Http.send_streaming!(get("/stream/slow").with_timeout(NoTimeout), {})?
	Stdout.line!("NoTimeout and the default idle timeout: ${text(default.read_to_end!(NoLimit)?)}")
}

## The `Request` timeout is a deadline for the whole exchange. The head of the
## slow response arrives within it, the body does not, and that is final.
deadline! : () => Try({}, _)
deadline! = || {
	request = get("/stream/slow").with_timeout(TimeoutMilliseconds(500))
	Stdout.line!("send!: ${Str.inspect(Http.send!(request, {}).map_ok(|response| response.status()))}")?

	destination : Path
	destination = "slow.txt"
	response = Http.send_streaming!(request, { idle_timeout: NoTimeout })?
	Stdout.line!("send_streaming!: status ${response.status().to_str()} before the deadline")?
	downloaded = File.with_writer!(destination, Truncate, {}, |writer| writer.write_stream!(response.chunks()))
	expect downloaded == Err(SourceErr(HttpErr(Timeout)))
	Stdout.line!("download: ${Str.inspect(downloaded)}")?
	Stdout.line!("written before the deadline: ${Str.inspect(destination.read_utf8!()?)}")?

	# Final: a new stream and `read_to_end!` report it again, at once.
	again = Stream.collect!(response.chunks())
	Stdout.line!("a new stream: ${Str.inspect(again)}")?
	Stdout.line!("read_to_end!: ${Str.inspect(response.read_to_end!(NoLimit))}")
}

## A body that breaks off fails the download with the chunks before it
## written, and the response reports the failure from then on.
broken_body! : () => Try({}, _)
broken_body! = || {
	destination : Path
	destination = "broken.bin"
	response = Http.send_streaming!(get("/stream/broken"), {})?
	Stdout.line!("status: ${response.status().to_str()}, ${Str.inspect(response.content_length())}")?
	downloaded = File.with_writer!(destination, Truncate, {}, |writer| writer.write_stream!(response.chunks()))
	expect downloaded == Err(SourceErr(HttpErr(BadBody)))
	Stdout.line!("download: ${Str.inspect(downloaded)}")?
	written = destination.read_bytes!()?
	Stdout.line!("written before the failure: ${written.len().to_str()} bytes, checksum ${checksum(written).to_str()}")?

	Stdout.line!("a new stream: ${Str.inspect(Stream.collect!(response.chunks()))}")?
	Stdout.line!("read_to_end!: ${Str.inspect(response.read_to_end!(MaxBytes(10)))}")
}

## A whole body through `write_stream!` arrives intact.
download! : () => Try({}, _)
download! = || {
	download_one!("/stream/sized", "sized.bin")?
	download_one!("/stream/chunked", "chunked.bin")
}

download_one! : Str, Path => Try({}, _)
download_one! = |path, destination| {
	response = Http.send_streaming!(get(path), {})?
	if response.status() != 200 {
		return Err(UnexpectedStatus(response.status()))
	}
	File.with_writer!(destination, RequireNew, {}, |writer| writer.write_stream!(response.chunks()))?
	written = destination.read_bytes!()?
	Stdout.line!("${destination.display()}: ${written.len().to_str()} bytes, checksum ${checksum(written).to_str()}")
}

## Calls through function values and methods beside an error of the caller's,
## and the failures that happen before there is a response.
error_rows! : U64 => Try({}, _)
error_rows! = |arg_count| {
	if arg_count > 1 {
		return Err(UnexpectedArguments)
	}
	send! = Http.send_streaming!
	read! = Http.StreamingResponse.read_to_end!

	response = send!(get("/utf8test"), {})?
	Stdout.line!("function values: ${text(read!(response, MaxBytes(64))?)}")?
	Stdout.line!("qualified: ${text(Http.StreamingResponse.read_to_end!(Http.send_streaming!(get("/utf8test"), {})?, NoLimit)?)}")?

	bad_url = Http.send_streaming!(Request.from_method(GET).with_uri("ftp://example.com"), {}).map_ok(|_| {})
	expect bad_url == Err(InvalidUrl(UnsupportedScheme("ftp")))
	Stdout.line!("invalid URL: ${Str.inspect(bad_url)}")?

	# Nothing listens on port 9: the failure is a transport error with a message.
	refused = Http.send_streaming!(Request.from_method(GET).with_uri("http://127.0.0.1:9/"), {}).map_ok(|_| {})
	match refused {
		Err(HttpErr(Other(message))) => Stdout.line!("refused connection: Other with a message: ${Str.inspect(!(message.is_empty()))}")
		other => Err(ExpectedARefusedConnection(other))
	}
}
