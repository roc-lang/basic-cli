## Shared buffered/streamed redirects against ci/rust_http_server.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "../platform/main.roc",
}

import pf.Http
import pf.OsStr
import pf.Stdout
import http.Request
import http.Response

check : Bool, Str -> Try({}, [CheckFailed(Str)])
check = |condition, message| if condition Ok({}) else Err(CheckFailed(message))

request : Str -> Request
request = |path| Request.from_method(GET).with_uri("http://127.0.0.1:9000${path}")

text : Response -> Str
text = |response| Str.from_utf8_lossy(Response.body(response))

main! : List(OsStr) => Try({}, _)
main! = |_| {
	# Disabled redirects return the original status, including invalid Location.
	for path in ["/redirect/malformed", "/redirect/duplicate", "/redirect/unsupported", "/redirect/non-utf8"] {
		response = Http.send_streaming!(request(path), {})?
		check(response.status() == 302, "redirects must be opt-in")?
	}
	missing = Http.send!(request("/redirect/missing"), { max_redirects: 1 })?
	check(missing.status() == 302 and text(missing) == "missing-location", "missing Location returns original response")?
	Stdout.line!("defaults and missing Location: ok")?

	# POST becomes GET on 301/302/303, while 307/308 preserve method and bytes.
	for status in [301.U16, 302, 303, 307, 308] {
		rewrite = status == 301 or status == 302 or status == 303
		original = request("/redirect/${status.to_str()}/echo").with_method(POST).with_body(Str.to_utf8("payload")).with_headers([
			{ name: "Content-Type", value: "application/custom" },
			{ name: "Content-Length", value: "999" },
			{ name: "Host", value: "wrong.invalid" },
			{ name: "Authorization", value: "secret" },
			{ name: "Cookie", value: "secret" },
			{ name: "Proxy-Authorization", value: "secret" },
			{ name: "Connection", value: "X-Hop" },
			{ name: "X-Hop", value: "private" },
			{ name: "X-Public", value: "kept" },
		])
		response = Http.send!(original, { max_redirects: 1 })?
		report = text(response)
		expected_method = if rewrite "GET" else "POST"
		expected_body = if rewrite "" else "payload"
		expected_type = if rewrite "<absent>" else "application/custom"
		check(report.contains("method: ${expected_method}\n") and report.contains("body: ${expected_body}\n"), "redirect method and body")?
		check(report.contains("content-type: ${expected_type}\n"), "body headers follow the rewritten body")?
		check(report.contains("authorization: secret\n") and report.contains("cookie: secret\n") and report.contains("proxy-authorization: secret\n"), "same-origin credentials survive")?
		check(report.contains("host: 127.0.0.1:9000\n") and !(report.contains("content-length: 999\n")), "authority and framing are recomputed")?
		check(report.contains("x-hop: <absent>\n") and report.contains("x-public: kept\n"), "hop headers are removed")?
	}
	# No implicit Content-Type may reappear after a rewritten POST.
	implicit = request("/redirect/302/echo").with_method(POST).with_body(Str.to_utf8("payload"))
	check(text(Http.send!(implicit, { max_redirects: 1 })?).contains("content-type: <absent>\n"), "implicit body header stays cleared")?
	# 301/302 preserve a non-POST method; 303 rewrites non-HEAD methods.
	for status in [301.U16, 302, 303] {
		put = request("/redirect/${status.to_str()}/echo").with_method(PUT).with_body(Str.to_utf8("payload"))
		expected_method = if status == 303 "GET" else "PUT"
		check(text(Http.send!(put, { max_redirects: 1 })?).contains("method: ${expected_method}\n"), "PUT rewrite rule")?
	}
	head = Http.send!(request("/redirect/303/echo").with_method(HEAD), { max_redirects: 1 })?
	check(head.headers().contains({ name: "x-request-method", value: "HEAD" }), "303 preserves HEAD")?
	Stdout.line!("method, body and framing rules: ok")?

	for target in ["cross", "network"] {
		original = request("/redirect/307/${target}").with_method(POST).with_body(Str.to_utf8("payload")).with_headers([
			{ name: "Authorization", value: "secret" },
			{ name: "Cookie", value: "secret" },
			{ name: "Proxy-Authorization", value: "secret" },
			{ name: "X-Public", value: "kept" },
		])
		report = text(Http.send!(original, { max_redirects: 1 })?)
		check(report.contains("authorization: <absent>\n") and report.contains("cookie: <absent>\n") and report.contains("proxy-authorization: <absent>\n"), "cross-origin credentials removed")?
		check(report.contains("host: localhost:9000\n") and report.contains("body: payload\n") and report.contains("x-public: kept\n"), "cross-origin destination and body")?
	}
	for path in ["/redirect/302/relative", "/redirect/fragment"] {
		check(text(Http.send!(request(path), { max_redirects: 1 })?).contains("uri: /redirect/inspect\n"), "relative redirect and fragment removal")?
	}
	check(text(Http.send!(request("/redirect/unicode"), { max_redirects: 1 })?).contains("uri: /redirect/inspect?name=caf%C3%A9\n"), "UTF-8 redirect references are preserved")?
	Stdout.line!("relative URLs and cross-origin credentials: ok")?

	duplicate = Http.send!(request("/redirect/duplicate"), { max_redirects: 1 }).map_ok(Response.status)
	check(duplicate == Err(HttpErr(AmbiguousRedirectLocation)), "duplicate Location rejected")?
	for path in ["/redirect/malformed", "/redirect/unsupported", "/redirect/non-utf8"] {
		match Http.send!(request(path), { max_redirects: 1 }) {
			Err(HttpErr(InvalidRedirectUrl(_))) => {}
			_ => {
				return Err(CheckFailed("invalid redirect rejected"))
			}
		}
	}
	looped = Http.send!(request("/redirect/loop"), { max_redirects: 2 }).map_ok(Response.status)
	check(looped == Err(HttpErr(RedirectLimitExceeded(2))), "redirect budget enforced")?
	final = Http.send!(request("/redirect/chain/2"), { max_redirects: 2 })?
	check(text(final) == "final", "exact redirect budget succeeds without reading intermediate bodies")?
	missing_final = Http.send!(request("/redirect/not-found"), { max_redirects: 1 })?
	check(missing_final.status() == 404 and text(missing_final) == "nothing here\n", "final status stays a response")?
	Stdout.line!("invalid locations, limits and final status: ok")?

	streamed = Http.send_streaming!(request("/redirect/chain/2"), { max_redirects: 2 })?
	check(Str.from_utf8_lossy(streamed.read_to_end!(NoLimit)?) == "final", "streamed redirects share the driver")?
	for path in ["/redirect/delayed/1", "/redirect/delayed/2"] {
		timed = request(path).with_timeout(TimeoutMilliseconds(650))
		result = Http.send!(timed, { max_redirects: 2 }).map_ok(Response.status)
		check(result == Err(HttpErr(Timeout)), "one deadline covers redirects and final body")?
	}
	Stdout.line!("streaming and overall deadlines: ok")
}
