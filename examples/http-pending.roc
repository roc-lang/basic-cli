## Keep a slow request in flight while other requests report on its progress.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
}

import pf.Duration
import pf.Http
import pf.OsStr
import pf.Stdout
import http.Request

# To run this example, first start the test server in another terminal:
#
#     cd ci/rust_http_server && cargo run --release
#
# then:
#
#     roc build examples/http-pending.roc
#     ./examples/http-pending
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# The server answers only after two seconds, as a server does with a long
	# commit. That is longer than a response normally takes, so the request
	# must not keep the default 30 second `idle_timeout`, which would end the
	# wait for a commit that takes minutes. `NoTimeout` leaves it to the
	# `Request` timeout, which is off by default.
	commit_request = Request.from_method(POST).with_uri("http://127.0.0.1:9000/delay/2000")

	# `start!` sends the request and returns at once, with a handle to the
	# response that is still to come.
	commit = Http.start!(commit_request, { idle_timeout: NoTimeout }) ? |err| CommitFailed(err)

	# Each `wait_within!` waits up to half a second for the commit. While it
	# waits it also moves the commit along, so the loop needs no `Sleep`. When
	# the commit has not finished by then, ask for its progress and wait again.
	var $progress_checks = 0.U64
	while True {
		match commit.wait_within!(Duration.millis(500)) {
			Ok(Ready(response)) => {
				# The commit's own response: status and headers are here, the
				# body is read as with `Http.send_streaming!`.
				body = response.read_to_end!(NoLimit) ? |err| CommitFailed(err)
				Stdout.line!("Checked progress while the commit ran: ${Str.inspect($progress_checks >= 2)}")?
				Stdout.line!("Commit finished with status ${response.status().to_str()}: ${Str.from_utf8_lossy(body)}")?
				break
			}
			Ok(NotReady) => {
				# Any other request can be sent now. The commit stays in flight.
				progress = Http.get_utf8!("http://127.0.0.1:9000/utf8test", {}) ? |err| ProgressFailed(err)
				$progress_checks = $progress_checks + 1
				Stdout.line!("Progress ${$progress_checks.to_str()}: ${progress}")?
			}
			Err(err) => {
				return Err(CommitFailed(err))
			}
		}
	}

	# To give up on a commit that is still running, call `commit.close!()`: the
	# request is cancelled and its connection closed. To wait for it without
	# checking on anything else, call `commit.wait!()`.
	Ok({})
}
