## Send HTTP requests and handle UTF-8, JSON, and transport failures.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import pf.OsStr
import pf.Http
import pf.Stdout
import http.Request
import http.Response

# To run this example, first start the test server in another terminal:
#
#     cd ci/rust_http_server && cargo run --release
#
# then:
#
#     roc build examples/http-client.roc
#     ./examples/http-client
main! : List(OsStr) => Try({}, _)
main! = |_args| run_demo!()

run_demo! : () => Try({}, _)
run_demo! = || {
	utf8 = Http.get_utf8!("http://127.0.0.1:9000/utf8test") ? |err| GetUtf8Failed(err)
	write_line!("I received '${utf8}' from the server.")?

	request = Request.from_method(GET).with_uri("http://127.0.0.1:9000/utf8test")
	response = Http.send!(request) ? |err| SendFailed(err)
	status = U16.to_str(Response.status(response))

	decoded : { foo : Str }
	decoded = Http.get!("http://127.0.0.1:9000") ? |err| GetJsonFailed(err)

	echo_request = Request.from_method(POST).with_uri("http://127.0.0.1:9000/echo-json")
	echo_response = Http.send_json!(echo_request, { foo: "Hello Json!" }) ? |err| SendJsonFailed(err)
	echoed : { foo : Str }
	echoed = Http.decode_json_response(echo_response) ? |err| EchoedJsonDecodeFailed(err)

	write_line!("The json I received was: { foo: \"${decoded.foo}\" }")?
	write_line!("send! returned status ${status}.")?
	write_line!("send_json! echoed: { foo: \"${echoed.foo}\" }.")?
	reject_invalid_json!()?
	reject_invalid_utf8!()?
	reject_invalid_url!()?

	Ok({})
}

reject_invalid_url! : () => Try({}, _)
reject_invalid_url! = || {
	result = Http.send!(Request.from_method(GET).with_uri("ftp://example.com"))

	match result {
		Err(InvalidUrl(UnsupportedScheme("ftp"))) => write_line!("invalid request URL was rejected.")
		Err(err) => Err(InvalidUrlRejectedWithWrongError(err))
		Ok(_) => Err(InvalidUrlUnexpectedlySucceeded)
	}
}

reject_invalid_json! : () => Try({}, _)
reject_invalid_json! = || {
	result : Try({ foo : Str }, _)
	result = Http.get!("http://127.0.0.1:9000/invalid-json")

	match result {
		Err(JsonErr(_)) => write_line!("invalid JSON was rejected.")
		Err(err) => Err(InvalidJsonRejectedWithWrongError(err))
		Ok(_) => Err(InvalidJsonUnexpectedlySucceeded)
	}
}

reject_invalid_utf8! : () => Try({}, _)
reject_invalid_utf8! = || {
	result = Http.get_utf8!("http://127.0.0.1:9000/invalid-utf8")

	match result {
		Err(BadBody(_)) => write_line!("invalid UTF-8 was rejected.")
		Err(err) => Err(InvalidUtf8RejectedWithWrongError(err))
		Ok(_) => Err(InvalidUtf8UnexpectedlySucceeded)
	}
}

write_line! : Str => Try({}, _)
write_line! = |message| Stdout.line!(message)
