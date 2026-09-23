import Host
import InternalHttp
import Url
import http.Request
import http.Response

## Send requests using the shared
## [`roc-lang/http`](https://github.com/roc-lang/http) `Request` and `Response`
## types. This module supplies effects and small JSON/UTF-8 conveniences while
## leaving pure request and response construction to that package.
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for HTTP protocol, TLS trust-store, and timeout details.
Http :: [].{

	## Errors raised by the host while sending a request, before a real HTTP
	## response is available.
	TransportErr : InternalHttp.TransportErr

	## Validate and send an HTTP request.
	##
	## The request URI must be an absolute HTTP or HTTPS URL accepted by Url.
	## Invalid URLs return InvalidUrl before any host effect occurs. Fragments
	## are removed because they are client-side identifiers and are not sent.
	##
	## ```roc
	## request = Request.from_method(GET).with_uri("https://www.roc-lang.org")
	## response = Http.send!(request)?
	## ```
	send! : Request => Try(Response, [InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send! = |request| {
		url = Url.parse(Request.uri(request)) ? InvalidUrl
		canonical_url = Url.without_fragment(url)
		canonical_request = request.with_uri(Url.to_str(canonical_url))
		host_response = Host.http_send_request!(InternalHttp.to_host_request(canonical_request)) ? HttpErr

		Ok(InternalHttp.from_host_response(host_response))
	}

	## Encode a value as JSON and set it as the request body.
	##
	## This uses Roc's builtin JSON encoder, so the value's type determines the
	## encoder through static dispatch.
	with_json_body : Request, _ => Try(Request, [JsonErr(_)])
	with_json_body = |request, value| {
		body = Json.to_str_try(value) ? JsonErr

		Ok(
			request
				.add_header("Content-Type", "application/json")
				.with_body(Str.to_utf8(body)),
		)
	}

	## Encode a value as JSON, attach it to the request body, and send it.
	send_json! : Request, _ => Try(Response, [JsonErr(_), InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send_json! = |request, value| {
		json_request = with_json_body(request, value)?

		send!(json_request)
	}

	## Perform an HTTP GET and decode the response body as a UTF-8 `Str`.
	##
	## The argument is a validated Url. Quoted literals work through
	## Url.from_quote; dynamic strings should be passed through Url.parse.
	##
	## ```roc
	## hello_str = Http.get_utf8!("http://localhost:8000")?
	## ```
	get_utf8! : Url.Url => Try(Str, [BadBody(Str), InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	get_utf8! = |url| {
		response = send!(Request.from_method(GET).with_uri(Url.to_str(url)))?
		body = Str.from_utf8(Response.body(response)) ? |_| BadBody("get_utf8!: response body was not valid UTF-8")

		Ok(body)
	}

	## Decode a response body as JSON.
	##
	## This uses Roc's builtin JSON parser, so the expected result type
	## determines the parser through static dispatch.
	decode_json_response : Response => Try(_, [BadBody(Str), JsonErr(_)])
	decode_json_response = |response| {
		body = Str.from_utf8(Response.body(response)) ? |_| BadBody("decode_json_response: response body was not valid UTF-8")
		decoded = Json.parse(body) ? JsonErr

		Ok(decoded)
	}

	## Perform an HTTP GET and decode the response body as JSON.
	##
	## The argument is a validated Url. JSON parser failures are returned as
	## JsonErr(_).
	##
	## ```roc
	## payload : Try({ foo : Str }, _)
	## payload = Http.get!("http://localhost:8000")
	## ```
	get! : Url.Url => Try(_, [BadBody(Str), InvalidUrl(Url.ParseErr), HttpErr(TransportErr), JsonErr(_)])
	get! = |url| {
		response = send!(Request.from_method(GET).with_uri(Url.to_str(url)))?

		decode_json_response(response)
	}
}
