import Duration
import Host
import InternalHttp
import Resource
import Url
import http.Method
import http.Header
import http.Request
import http.Response

## Send requests using the shared
## [`roc-lang/http`](https://github.com/roc-lang/http) `Request` and `Response`
## types. This module supplies effects and small JSON/UTF-8 conveniences while
## leaving pure request and response construction to that package.
##
## [Http.send!] and the functions built on it hold the whole response body in
## memory. [Http.send_streaming!] returns as soon as the status and headers
## have arrived and hands the body over as a `Stream` of chunks, for a
## download larger than memory or one whose progress is shown.
##
## No default `User-Agent` is sent. APIs such as
## [GitHub's REST API](https://docs.github.com/en/rest/using-the-rest-api/getting-started-with-the-rest-api#user-agent)
## require one; add it to the request before calling [Http.send!] or
## [Http.send_streaming!]:
##
## ```roc
## request = Request.from_method(GET)
##     .with_uri("https://api.github.com/repos/roc-lang/basic-cli")
##     .add_header("User-Agent", "my-roc-cli")
## response = Http.send!(request, {})?
## ```
##
## If the request has no `Content-Type` header, the platform currently adds
## `Content-Type: text/plain`, including for a bodyless GET. An explicit
## content type is preserved. [Issue #531](https://github.com/roc-lang/basic-cli/issues/531)
## tracks changes to these defaults.
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for HTTP protocol, TLS trust-store, and timeout details.
Http :: [].{

	## Failures while sending a request, reading its body or following redirects.
	TransportErr : [Timeout, NetworkError, BadBody, Other(List(U8)), RedirectLimitExceeded(U64), InvalidRedirectUrl(Url.ParseErr), AmbiguousRedirectLocation, InsecureRedirect]

	## Redirects are opt-in; `{}` returns the first response unchanged.
	## A positive maximum follows 301/302/303/307/308, using one request
	## deadline across every hop and the final body. Cross-origin requests
	## discard credentials; HTTPS-to-HTTP redirects are rejected.
	SendOptions := { max_redirects : U64 ?? 0 }

	## Validate and send an HTTP request.
	##
	## The request URI must be an absolute HTTP or HTTPS URL accepted by Url.
	## Invalid URLs return InvalidUrl before any host effect occurs. Fragments
	## are removed because they are client-side identifiers and are not sent.
	##
	## ```roc
	## request = Request.from_method(GET).with_uri("https://www.roc-lang.org")
	## response = Http.send!(request, {})?
	## ```
	send! : Request, SendOptions => Try(Response, [Interrupted, InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send! = |request, options| {
		response = send_streaming!(request, { idle_timeout: NoTimeout, max_redirects: options.max_redirects })?
		body = match response.read_to_end!(NoLimit) {
			Ok(bytes) => bytes
			Err(ReadLimitExceeded(_)) => {
				return Err(HttpErr(BadBody))
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
			Err(HttpErr(error)) => {
				return Err(HttpErr(error))
			}
		}
		Ok(Response.from_status(response.status).with_headers(response.headers).with_body(body))
	}

	## Encode a value as JSON and set it as the request body.
	##
	## This uses Roc's builtin JSON encoder, so the value's type determines the
	## encoder through static dispatch.
	with_json_body : Request, _ -> Try(Request, [JsonErr(_)])
	with_json_body = |request, value| {
		body = Json.to_str_try(value) ? JsonErr

		Ok(
			request
				.add_header("Content-Type", "application/json")
				.with_body(Str.to_utf8(body)),
		)
	}

	## Encode a value as JSON, attach it to the request body, and send it.
	send_json! : Request, _, SendOptions => Try(Response, [Interrupted, JsonErr(_), InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send_json! = |request, value, options| {
		json_request = with_json_body(request, value)?

		send!(json_request, options)
	}

	## Perform an HTTP GET and decode the response body as a UTF-8 `Str`.
	##
	## The argument is a validated Url. Quoted literals work through
	## Url.from_quote; dynamic strings should be passed through Url.parse.
	##
	## ```roc
	## hello_str = Http.get_utf8!("http://localhost:8000", {})?
	## ```
	get_utf8! : Url.Url, SendOptions => Try(Str, [Interrupted, BadBody(Str), InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	get_utf8! = |url, options| {
		response = send!(Request.from_method(GET).with_uri(Url.to_str(url)), options)?
		body = Str.from_utf8(Response.body(response)) ? |_| BadBody("get_utf8!: response body was not valid UTF-8")

		Ok(body)
	}

	## Decode a response body as JSON.
	##
	## This uses Roc's builtin JSON parser, so the expected result type
	## determines the parser through static dispatch.
	decode_json_response : Response -> Try(_, [BadBody(Str), JsonErr(_)])
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
	## payload = Http.get!("http://localhost:8000", {})
	## ```
	get! : Url.Url, SendOptions => Try(_, [Interrupted, BadBody(Str), InvalidUrl(Url.ParseErr), HttpErr(TransportErr), JsonErr(_)])
	get! = |url, options| {
		response = send!(Request.from_method(GET).with_uri(Url.to_str(url)), options)?

		decode_json_response(response)
	}

	## Options for [Http.send_streaming!]. `{}` selects the defaults.
	##
	## `idle_timeout` bounds each single wait: for the status and headers, and
	## then for each part of the body. A server that is silent for that long
	## has stalled, however much it has already sent. It defaults to 30
	## seconds; `After(Duration.zero)` expires at once, before anything is
	## sent, and `NoTimeout` waits for as long as the server takes.
	##
	## The timeout of the `Request` keeps its meaning: it is the deadline for
	## the whole exchange, body included, and `NoTimeout` (its default) and
	## `TimeoutMilliseconds(0)` both mean no deadline. For a large download
	## leave the request at `NoTimeout` and rely on `idle_timeout`.
	##
	## `max_redirects` has the same meaning as the `max_redirects` field of [SendOptions].
	## A caught pending signal returns bare `Interrupted` from a wait. Body
	## reads preserve their cursor and collected bytes after interruption;
	## acknowledge the signal before reading again. The deadline keeps running.
	StreamingOptions := { idle_timeout : [NoTimeout, After(Duration)] ?? After(Duration.seconds(30)), max_redirects : U64 ?? 0 }

	## Validate and send an HTTP request, returning once the status and
	## headers have arrived. The body is read afterwards, through the
	## [StreamingResponse].
	##
	## The request is validated, built and sent exactly as [Http.send!] does
	## it. Any status is `Ok`, so check it before reading the body. Either
	## timeout expiring is `Err(HttpErr(Timeout))`.
	##
	## ```roc
	## request = Request.from_method(GET).with_uri(url.to_str())
	## response = Http.send_streaming!(request, {})?
	## if response.status() != 200 {
	##     return Err(UnexpectedStatus(response.status()))
	## }
	## File.with_writer!(destination, Truncate, {}, |writer| writer.write_stream!(response.chunks()))?
	## ```
	send_streaming! : Request, StreamingOptions => Try(StreamingResponse, [Interrupted, InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send_streaming! = |request, options| {
		url = Url.parse(Request.uri(request)) ? InvalidUrl
		canonical = Url.without_fragment(url)
		headers = Request.headers(request)
		initial_headers = if headers.any(|header| header.name.with_ascii_lowercased() == "content-type") {
			headers
		} else {
			headers.append({ name: "Content-Type", value: "text/plain" })
		}
		canonical_request = request.with_uri(canonical.to_str()).with_headers(initial_headers)
		deadline = match Request.timeout(request) {
			NoTimeout | TimeoutMilliseconds(0) => NoTimeout
			TimeoutMilliseconds(ms) => At(Host.monotonic_now!().plus_saturated(ms.times_saturated(1_000_000)))
		}
		send_redirected!(canonical_request, canonical, options, options.max_redirects, deadline)
	}

	## The status and headers of a response, and its body still to be read.
	##
	## The body arrives over the response's own connection as it is read.
	## [StreamingResponse.chunks] and [read_to_end!] read from one shared
	## cursor, as do copies of the response, so each byte of the body is
	## returned once.
	##
	## The connection is closed when the body ends, when a failure other than
	## an idle timeout ends it, or when the last reference to the response and
	## its streams is released; a body that is not wanted need not be read.
	StreamingResponse :: {
		status : U16,
		headers : List(Header.Header),
		content_length : [Known(U64), Unknown],
		host : Resource.HttpResponse,
	}.{

		## Render the status and headers without exposing the host handle.
		to_inspect : StreamingResponse -> Str
		to_inspect = |response|
			"Http.StreamingResponse({ status: ${response.status.to_str()}, headers: ${Str.inspect(response.headers)}, content_length: ${Str.inspect(response.content_length)} })"

		## The status code. Any status is a response: a 404 is `Ok` with
		## `status()` 404, and its body can be read or left alone.
		status : StreamingResponse -> U16
		status = |response| response.status

		## The response headers, in the order they arrived.
		headers : StreamingResponse -> List(Header.Header)
		headers = |response| response.headers

		## The length of the whole body in bytes, from the `Content-Length`
		## header. `Unknown` when the server did not send one, as with a
		## chunked body. For the response to a `HEAD` request this is the
		## length the header declares, although no body follows.
		content_length : StreamingResponse -> [Known(U64), Unknown]
		content_length = |response| response.content_length

		## Lazily read the body as non-empty chunks of at most 64 KiB. Chunk
		## boundaries are chosen by the host and carry no meaning.
		##
		## Building the stream reads nothing; each item is one read from the
		## shared cursor. The stream ends at the end of the body, and a
		## failure is the last item.
		##
		## After an idle timeout, `Err(HttpErr(Timeout))` with the response's
		## deadline not yet reached, the response stays usable and a new
		## `chunks()` continues where the last one stopped. Any other failure
		## is final: a new stream yields it again.
		##
		## ```roc
		## response = Http.send_streaming!(request, { idle_timeout: After(Duration.seconds(5)) })?
		## var $done = 0
		## for! item in response.chunks() {
		##     bytes = item?
		##     $done = $done + bytes.len()
		## }
		## ```
		##
		## Process chunks individually to bound memory; `Stream.collect!`
		## accumulates every chunk.
		chunks : StreamingResponse -> Stream(Try(List(U8), [Interrupted, HttpErr(TransportErr)]))
		chunks = |response|
			# Keep the response in the state, not the callback capture, so
			# Finished can release it even when the terminal continuation is
			# retained.
			Stream.custom(
				Reading(response),
				Unknown,
				|state|
					match state {
						Finished => Err(NoMore)
						Reading(current) =>
							match Host.http_read_body!(current.host, Chunk) {
								Ok(bytes) => Ok((Ok(bytes), Reading(current)))
								Err(EndOfBody) => Err(NoMore)
								Err(HttpErr(err)) => Ok((Err(transport_error(err)), Finished))
								# Only a read to the end has a limit to exceed.
								Err(ReadLimitExceeded) => Ok((Err(HttpErr(Other("the host limited a chunk read".to_utf8()))), Finished))
							}
					},
			)

		## Read the rest of the body: everything [StreamingResponse.chunks]
		## and earlier reads have not returned. At the end of the body that is
		## `Ok([])`.
		##
		## With `MaxBytes(max)` this fails with `ReadLimitExceeded(max)` as
		## soon as more than `max` unread bytes have arrived, without waiting
		## for the rest. `NoLimit` holds the whole remainder in memory.
		##
		## A failed call consumes nothing it could keep: after
		## `ReadLimitExceeded` or an idle timeout the bytes that had arrived
		## are still unread, so [StreamingResponse.chunks] or another call
		## continues from the same place.
		##
		## ```roc
		## body = response.read_to_end!(MaxBytes(1_048_576))?
		## ```
		read_to_end! : StreamingResponse, [NoLimit, MaxBytes(U64)] => Try(List(U8), [Interrupted, ReadLimitExceeded(U64), HttpErr(TransportErr)])
		read_to_end! = |response, limit| {
			max = match limit {
				NoLimit => U64.highest
				MaxBytes(max_bytes) => max_bytes
			}
			match Host.http_read_body!(response.host, ToEnd(max)) {
				Ok(bytes) => Ok(bytes)
				Err(ReadLimitExceeded) => Err(ReadLimitExceeded(max))
				Err(HttpErr(err)) => Err(transport_error(err))
				# A read to the end returns an empty remainder instead.
				Err(EndOfBody) => Ok([])
			}
		}
	}
}

# `{}` asks for the default idle timeout; a field given replaces it.
expect Http.StreamingOptions.{}.idle_timeout == After(Duration.seconds(30))
expect Http.StreamingOptions.{ idle_timeout: NoTimeout }.idle_timeout == NoTimeout
expect Http.StreamingOptions.{ idle_timeout: After(Duration.zero) }.idle_timeout == After(Duration.nanos(0))

## Convert raw transport errors to the public open error row.
transport_error : InternalHttp.TransportErr -> [Interrupted, HttpErr(Http.TransportErr)]
transport_error = |error|
	match error {
		Interrupted => Interrupted
		Timeout => HttpErr(Timeout)
		NetworkError => HttpErr(NetworkError)
		BadBody => HttpErr(BadBody)
		Other(message) => HttpErr(Other(message))
	}

## The same driver serves buffered and streamed responses. The deadline is
## captured once and is passed unchanged to every native hop and final body.
send_redirected! : Request, Url.Url, Http.StreamingOptions, U64, [NoTimeout, At(U64)] => Try(Http.StreamingResponse, [Interrupted, HttpErr(Http.TransportErr)])
send_redirected! = |request, url, options, remaining, deadline| {
	idle = match options.idle_timeout {
		NoTimeout => NoTimeout
		After(duration) => After(duration.to_nanos())
	}
	hop = request.with_headers(sanitize_headers(Request.headers(request), False, False))
	raw = match Host.http_send_streaming!(InternalHttp.to_host_request(hop), idle, deadline) {
		Ok(value) => value
		Err(error) => {
			return Err(transport_error(error))
		}
	}
	response = Http.StreamingResponse.{ status: raw.status, headers: InternalHttp.from_host_headers(raw.headers), content_length: raw.content_length, host: raw.body }
	status = response.status
	redirect = status == 301 or status == 302 or status == 303 or status == 307 or status == 308
	if options.max_redirects == 0 or !redirect {
		return Ok(response)
	}
	locations = response.headers.keep_if(|header| header.name.with_ascii_lowercased() == "location")
	location = match locations {
		[] => {
			return Ok(response)
		}
		[header] => header.value
		_ => {
			Host.http_close_body!(response.host)
			return Err(HttpErr(AmbiguousRedirectLocation))
		}
	}
	Host.http_close_body!(response.host)
	if remaining == 0 {
		return Err(HttpErr(RedirectLimitExceeded(options.max_redirects)))
	}
	match raw.invalid_location {
		Some(byte) => {
			return Err(HttpErr(InvalidRedirectUrl(InvalidCharacter(byte))))
		}
		None => {}
	}
	next_url = redirect_url(url, location) ? |error| HttpErr(InvalidRedirectUrl(error))
	if Url.scheme(url) == Https and Url.scheme(next_url) == Http {
		return Err(HttpErr(InsecureRedirect))
	}
	next = redirected_request(request, url, next_url, status)
	send_redirected!(next, next_url, options, remaining - 1, deadline)
}

## HTTP permits network-path references; Url.resolve deliberately does not.
redirect_url : Url.Url, Str -> Try(Url.Url, Url.ParseErr)
redirect_url = |base, location| {
	resolved = if location.starts_with("//") {
		scheme = match Url.scheme(base) {
			Http => "http:"
			Https => "https:"
		}
		Url.parse(Str.concat(scheme, location))
	} else {
		# A colon in the first path segment denotes a URI scheme, including
		# schemes we reject; do not reinterpret it as a relative pathname.
		absolute = match location.split_first(":") {
			Ok({ before, .. }) => !before.contains("/") and !before.contains("?") and !before.contains("#")
			Err(NotFound) => False
		}
		if absolute {
			Url.parse(location)
		} else {
			Url.resolve(base, location)
		}
	}
	resolved.map_ok(Url.without_fragment)
}

same_origin : Url.Url, Url.Url -> Bool
same_origin = |left, right|
	Url.scheme(left) == Url.scheme(right) and Url.host(left) == Url.host(right) and Url.port(left) == Url.port(right)

redirected_request : Request, Url.Url, Url.Url, U16 -> Request
redirected_request = |request, old_url, next_url, status| {
	method = Request.method(request)
	rewrite = ((status == 301 or status == 302) and method == POST) or (status == 303 and method != HEAD)
	headers = sanitize_headers(Request.headers(request), !same_origin(old_url, next_url), rewrite)
	prepared = request.with_uri(next_url.to_str()).with_headers(headers)
	if rewrite {
		prepared.with_method(GET).with_body([])
	} else {
		prepared
	}
}

## Recompute framing and authority. Connection-nominated fields are hop-local.
sanitize_headers : List(Header.Header), Bool, Bool -> List(Header.Header)
sanitize_headers = |headers, cross_origin, drop_body| {
	connection_values = headers.keep_if(|header| header.name.with_ascii_lowercased() == "connection").map(|header| header.value)
	connection_names = Str.join_with(connection_values, ",").split_on(",").map(|name| name.trim().with_ascii_lowercased())
	headers.keep_if(
		|header| {
			name = header.name.with_ascii_lowercased()
			hop = name == "host" or name == "content-length" or name == "connection" or name == "keep-alive" or name == "proxy-connection" or name == "te" or name == "trailer" or name == "transfer-encoding" or name == "upgrade" or connection_names.contains(name)
			secret = cross_origin and (name == "authorization" or name == "cookie" or name == "proxy-authorization")
			body = drop_body and (name.starts_with("content-") or name == "digest" or name == "expect")
			!hop and !secret and !body
		},
	)
}

expect Http.SendOptions.{}.max_redirects == 0
expect Http.StreamingOptions.{}.max_redirects == 0
expect redirect_url("https://example.com/a/b", "../c#part") == Url.parse("https://example.com/c")
expect redirect_url("https://example.com/a", "//other.example/b") == Url.parse("https://other.example/b")
expect same_origin("https://EXAMPLE.com:443/a", "https://example.com/b")
expect !same_origin("http://example.com/", "https://example.com/")

expect {
	request = Request.from_method(POST).with_body([1, 2]).with_headers([
		{ name: "Authorization", value: "secret" },
		{ name: "Cookie", value: "secret" },
		{ name: "Content-Type", value: "application/json" },
		{ name: "Connection", value: "X-Private" },
		{ name: "X-Private", value: "hop" },
		{ name: "X-Public", value: "kept" },
	])
	next = redirected_request(request, "https://a.example/", "https://b.example/", 302)
	Request.method(next) == GET and Request.body(next) == [] and Request.headers(next) == [{ name: "X-Public", value: "kept" }]
}
