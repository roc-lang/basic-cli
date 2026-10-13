import Duration
import Host
import InternalHttp
import Resource
import Url
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
	## payload = Http.get!("http://localhost:8000")
	## ```
	get! : Url.Url => Try(_, [BadBody(Str), InvalidUrl(Url.ParseErr), HttpErr(TransportErr), JsonErr(_)])
	get! = |url| {
		response = send!(Request.from_method(GET).with_uri(Url.to_str(url)))?

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
	StreamingOptions := { idle_timeout : [NoTimeout, After(Duration)] ?? After(Duration.seconds(30)) }

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
	## File.with_writer!(destination, Truncate, |writer| writer.write_stream!(response.chunks()))?
	## ```
	send_streaming! : Request, StreamingOptions => Try(StreamingResponse, [InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	send_streaming! = |request, options| {
		url = Url.parse(Request.uri(request)) ? InvalidUrl
		canonical_url = Url.without_fragment(url)
		canonical_request = request.with_uri(Url.to_str(canonical_url))
		host_idle_timeout = match options.idle_timeout {
			NoTimeout => NoTimeout
			After(duration) => After(duration.to_nanos())
		}
		# A tag union that crosses the host boundary is closed by design, so
		# the transport error is rebuilt under `HttpErr`, in an open union that
		# `?` can combine with a caller's other errors.
		match Host.http_send_streaming!(InternalHttp.to_host_request(canonical_request), host_idle_timeout) {
			Ok(response) =>
				Ok(
					StreamingResponse.{
						status: response.status,
						headers: InternalHttp.from_host_headers(response.headers),
						content_length: response.content_length,
						host: response.body,
					},
				)
			Err(err) => Err(HttpErr(err))
		}
	}

	## The status and headers of a response, and its body still to be read.
	##
	## The body arrives over the response's own connection as it is read.
	## [chunks] and [read_to_end!] read from one shared cursor, as do copies of
	## the response, so each byte of the body is returned once.
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
		chunks : StreamingResponse -> Stream(Try(List(U8), [HttpErr(TransportErr)]))
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
								Err(HttpErr(err)) => Ok((Err(HttpErr(err)), Finished))
								# Only a read to the end has a limit to exceed.
								Err(ReadLimitExceeded) => Ok((Err(HttpErr(Other("the host limited a chunk read".to_utf8()))), Finished))
							}
					},
			)

		## Read the rest of the body: everything [chunks] and earlier reads
		## have not returned. At the end of the body that is `Ok([])`.
		##
		## With `MaxBytes(max)` this fails with `ReadLimitExceeded(max)` as
		## soon as more than `max` unread bytes have arrived, without waiting
		## for the rest. `NoLimit` holds the whole remainder in memory.
		##
		## A failed call consumes nothing it could keep: after
		## `ReadLimitExceeded` or an idle timeout the bytes that had arrived
		## are still unread, so [chunks] or another call continues from the
		## same place.
		##
		## ```roc
		## body = response.read_to_end!(MaxBytes(1_048_576))?
		## ```
		read_to_end! : StreamingResponse, [NoLimit, MaxBytes(U64)] => Try(List(U8), [ReadLimitExceeded(U64), HttpErr(TransportErr)])
		read_to_end! = |response, limit| {
			max = match limit {
				NoLimit => U64.highest
				MaxBytes(max_bytes) => max_bytes
			}
			match Host.http_read_body!(response.host, ToEnd(max)) {
				Ok(bytes) => Ok(bytes)
				Err(ReadLimitExceeded) => Err(ReadLimitExceeded(max))
				Err(HttpErr(err)) => Err(HttpErr(err))
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
