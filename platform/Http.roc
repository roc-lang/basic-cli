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
## [Http.start!] sends a request without waiting for it, so that other work,
## including other requests, can go on while it is in flight.
##
## Requests default to `User-Agent: roc-basic-cli/0.26`. An explicit
## `User-Agent` is preserved, regardless of the header name's casing.
## A non-empty body defaults to `Content-Type: text/plain`; an empty body
## adds no content type. Explicit content types are always preserved.
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

	## Options for [Http.send_streaming!] and [Http.start!]. `{}` selects the
	## defaults.
	##
	## `idle_timeout` bounds each single wait: for the status and headers, and
	## then for each part of the body. A server that is silent for that long
	## has stalled, however much it has already sent. It defaults to 30
	## seconds; `After(Duration.zero)` expires at once, before anything is
	## sent, and `NoTimeout` waits for as long as the server takes. For
	## [Http.start!], the wait for the status and headers counts from
	## `start!`, or from the redirect that led to the hop, rather than from
	## the call that waits; see [Http.start!].
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
		canonical_request = request_with_defaults(request.with_uri(canonical.to_str()))
		send_redirected!(canonical_request, canonical, options, options.max_redirects, request_deadline!(request))
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
				Err(Unknown),
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

	## Start sending a request and return without waiting for its response.
	## Wait for the response with [PendingResponse.wait_within!] or
	## [PendingResponse.wait!]. Meanwhile the app can do other work,
	## including other requests and other pending requests.
	##
	## The request is validated, built and sent as [Http.send_streaming!]
	## does it, with the same [StreamingOptions], and the waits return the
	## same [StreamingResponse] and the same errors. Besides an invalid URL,
	## `start!` fails only when the host cannot hold another request; every
	## failure of the request itself, including one to build it, is returned
	## by the waits. `start!` does not wait, so a pending signal does not
	## stop it.
	##
	## **When a request makes progress.** basic-cli runs no background
	## thread. A pending request is sent, and its response received, only
	## while the app is inside an HTTP call: `start!` itself, [Http.send!] and
	## the functions built on it, [Http.send_streaming!], a body read, and
	## above all [PendingResponse.wait_within!] and [PendingResponse.wait!]. In
	## between, for example during `Sleep.millis!`, a command or file I/O,
	## the operating system buffers what arrives, up to a limit. A request
	## with a large body, or a server that sends a lot before its status
	## line, can stall until the next such call. Wait with
	## [PendingResponse.wait_within!] instead of sleeping to keep requests
	## moving.
	##
	## Both timeouts count from `start!`, also while the request is not
	## making progress. The timeout of the `Request` stays the deadline for
	## the whole exchange, across redirects and the body. `idle_timeout`
	## bounds the time each hop has for its status and headers, counted from
	## `start!` or from the redirect that led to the hop, and then each wait
	## for part of the body. Status and headers that the host received in
	## time are returned by a later wait, however late it comes; the body
	## then has the timeouts of any [StreamingResponse]. For a server that
	## takes long to answer, set a larger `idle_timeout`, or `NoTimeout`.
	##
	## ```roc
	## commit = Http.start!(commit_request, { idle_timeout: NoTimeout })?
	## while True {
	##     match commit.wait_within!(Duration.seconds(1))? {
	##         Ready(response) => {
	##             report!(response)?
	##             break
	##         }
	##         NotReady => show_progress!(Http.send!(progress_request, {})?)?
	##     }
	## }
	## ```
	start! : Request, StreamingOptions => Try(PendingResponse, [InvalidUrl(Url.ParseErr), HttpErr(TransportErr)])
	start! = |request, options| {
		url = Url.parse(Request.uri(request)) ? InvalidUrl
		canonical = Url.without_fragment(url)
		canonical_request = request_with_defaults(request.with_uri(canonical.to_str()))
		hop = canonical_request.with_headers(sanitize_headers(Request.headers(canonical_request), False, False))
		match Host.http_start!(InternalHttp.to_host_request(hop), host_idle_timeout(options.idle_timeout), request_deadline!(request)) {
			Ok(host) => Ok(PendingResponse.{ host, request: canonical_request, url: canonical, max_redirects: options.max_redirects })
			Err(message) => Err(HttpErr(Other(message)))
		}
	}

	## A request started with [Http.start!] whose response may not have
	## arrived yet.
	##
	## Copies of a pending response share one request. Once its response has
	## arrived, every wait returns that same [StreamingResponse], and all of
	## them read its body from one cursor. Until the pending response is
	## released it keeps the request, body included, and the connection of
	## a response that has arrived.
	##
	## The request is cancelled and its connection closed when the last
	## reference to the pending response is released, or earlier by
	## [close!]. A response already returned stays readable until it, too,
	## is released.
	PendingResponse :: { host : Resource.HttpPending, request : Request, url : Url.Url, max_redirects : U64 }.{

		## Render the pending response without exposing its host handle.
		to_inspect : PendingResponse -> Str
		to_inspect = |_| "Http.PendingResponse(<opaque>)"

		## Check on the request, waiting up to `wait` for its status and
		## headers: `Ready(response)` once they have arrived, otherwise
		## `NotReady`, which leaves the request in flight.
		##
		## `Duration.zero` returns at once, with a response whose status and
		## headers the host has already received. A redirect that has arrived
		## then only starts the next hop, so the result is `NotReady` until
		## the response to that hop has arrived too. A wait also moves every
		## other pending request along (see [Http.start!]), so a loop of
		## `wait_within!` calls needs no separate sleep. Redirects whose
		## response arrives during a longer wait are followed within it.
		##
		## Either timeout of the request expiring is `Err(HttpErr(Timeout))`,
		## and every later wait returns it again. A caught pending signal is
		## `Err(Interrupted)` and keeps the request; acknowledge the signal
		## before waiting again. After [close!] this is `Err(Closed)`.
		wait_within! : PendingResponse, Duration => Try([Ready(StreamingResponse), NotReady], [Closed, Interrupted, HttpErr(TransportErr)])
		wait_within! = |pending, wait|
			match wait_pending!(pending, At(Host.monotonic_now!().plus_saturated(wait.to_nanos()))) {
				Ok(Ready(response)) => Ok(Ready(response))
				Ok(NotReady) => Ok(NotReady)
				Err(Closed) => Err(Closed)
				Err(Interrupted) => Err(Interrupted)
				Err(HttpErr(err)) => Err(HttpErr(err))
			}

		## Wait for the status and headers, as [Http.send_streaming!] would
		## have, bounded only by the timeouts of the request. Errors are those
		## of [wait_within!].
		wait! : PendingResponse => Try(StreamingResponse, [Closed, Interrupted, HttpErr(TransportErr)])
		wait! = |pending|
			match wait_pending!(pending, NoTimeout) {
				Ok(Ready(response)) => Ok(response)
				# Cannot happen: a wait without a limit of its own ends only
				# with the response or an error.
				Ok(NotReady) => wait!(pending)
				Err(Closed) => Err(Closed)
				Err(Interrupted) => Err(Interrupted)
				Err(HttpErr(err)) => Err(HttpErr(err))
			}

		## Cancel the request if it is still in flight and close its
		## connection, for every copy of the pending response. A response
		## already returned is not affected. Afterwards [wait_within!] and [wait!]
		## return `Err(Closed)`. Closing again does nothing.
		close! : PendingResponse => {}
		close! = |pending| Host.http_pending_close!(pending.host)
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

## The request timeout as an instant on the `monotonic_now!` clock. It is
## captured once, so that it covers every hop and the final body.
request_deadline! : Request => [NoTimeout, At(U64)]
request_deadline! = |request|
	match Request.timeout(request) {
		NoTimeout | TimeoutMilliseconds(0) => NoTimeout
		TimeoutMilliseconds(ms) => At(Host.monotonic_now!().plus_saturated(ms.times_saturated(1_000_000)))
	}

## The idle timeout as the host takes it, in nanoseconds.
host_idle_timeout : [NoTimeout, After(Duration)] -> [NoTimeout, After(U64)]
host_idle_timeout = |idle_timeout|
	match idle_timeout {
		NoTimeout => NoTimeout
		After(duration) => After(duration.to_nanos())
	}

## The same driver serves buffered and streamed responses. The deadline is
## captured once and is passed unchanged to every native hop and final body.
send_redirected! : Request, Url.Url, Http.StreamingOptions, U64, [NoTimeout, At(U64)] => Try(Http.StreamingResponse, [Interrupted, HttpErr(Http.TransportErr)])
send_redirected! = |request, url, options, remaining, deadline| {
	hop = request.with_headers(sanitize_headers(Request.headers(request), False, False))
	raw = match Host.http_send_streaming!(InternalHttp.to_host_request(hop), host_idle_timeout(options.idle_timeout), deadline) {
		Ok(value) => value
		Err(error) => {
			return Err(transport_error(error))
		}
	}
	match redirect_step!(raw, request, url, options.max_redirects, remaining)? {
		Final(response) => Ok(response)
		Follow(next) => send_redirected!(next.request, next.url, options, remaining - 1, deadline)
	}
}

## What the response to one hop means for a request that may follow
## redirects: the final response, or the next hop to send. The body of a
## redirect is closed.
redirect_step! : InternalHttp.StreamingResponseFromHost, Request, Url.Url, U64, U64 => Try([Final(Http.StreamingResponse), Follow({ request : Request, url : Url.Url, status : U16, location : Str })], [HttpErr(Http.TransportErr)])
redirect_step! = |raw, request, url, max_redirects, remaining| {
	response = Http.StreamingResponse.{ status: raw.status, headers: InternalHttp.from_host_headers(raw.headers), content_length: raw.content_length, host: raw.body }
	status = response.status
	redirect = status == 301 or status == 302 or status == 303 or status == 307 or status == 308
	if max_redirects == 0 or !redirect {
		return Ok(Final(response))
	}
	locations = response.headers.keep_if(|header| header.name.with_ascii_lowercased() == "location")
	location = match locations {
		[] => {
			return Ok(Final(response))
		}
		[header] => header.value
		_ => {
			Host.http_close_body!(response.host)
			return Err(HttpErr(AmbiguousRedirectLocation))
		}
	}
	Host.http_close_body!(response.host)
	if remaining == 0 {
		return Err(HttpErr(RedirectLimitExceeded(max_redirects)))
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
	Ok(Follow({ request: redirected_request(request, url, next_url, status), url: next_url, status, location }))
}

## The request, URL and remaining redirects of the hop a pending response is
## on: its first request with each redirect the host has followed applied
## again, in order. Each passed [redirect_step!] when it was followed, so
## applying it again gives the same hop.
current_hop : Http.PendingResponse, List((U16, Str)) -> Try({ request : Request, url : Url.Url, remaining : U64 }, [HttpErr(Http.TransportErr)])
current_hop = |pending, followed| {
	var $hop = { request: pending.request, url: pending.url, remaining: pending.max_redirects }
	for (status, location) in followed {
		next_url = redirect_url($hop.url, location) ? |error| HttpErr(InvalidRedirectUrl(error))
		$hop = { request: redirected_request($hop.request, $hop.url, next_url, status), url: next_url, remaining: $hop.remaining - 1 }
	}
	Ok($hop)
}

## Wait until `until` for the final response of a pending request, sending
## each redirect hop as soon as its response arrives. One `until` covers
## every hop.
wait_pending! : Http.PendingResponse, [NoTimeout, At(U64)] => Try([Ready(Http.StreamingResponse), NotReady], [Closed, Interrupted, HttpErr(Http.TransportErr)])
wait_pending! = |pending, until| {
	ready = match Host.http_pending_wait!(pending.host, until) {
		Ok(Ready(value)) => value
		Ok(NotReady) => {
			return Ok(NotReady)
		}
		Err(Closed) => {
			return Err(Closed)
		}
		Err(HttpErr(error)) => {
			return Err(transport_error(error))
		}
	}
	hop = match ready.redirects {
		[] => { request: pending.request, url: pending.url, remaining: pending.max_redirects }
		followed => current_hop(pending, followed)?
	}
	match redirect_step!(ready.response, hop.request, hop.url, pending.max_redirects, hop.remaining)? {
		Final(response) => Ok(Ready(response))
		Follow(next) => {
			sent = next.request.with_headers(sanitize_headers(Request.headers(next.request), False, False))
			Host.http_pending_follow!(pending.host, InternalHttp.to_host_request(sent), next.status, next.location)
			wait_pending!(pending, until)
		}
	}
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

## Apply request defaults once, before redirect rewriting can remove body headers.
request_with_defaults : Request -> Request
request_with_defaults = |request| {
	headers = Request.headers(request)
	with_agent = if headers.any(|header| header.name.with_ascii_lowercased() == "user-agent") {
		headers
	} else {
		headers.append({ name: "User-Agent", value: "roc-basic-cli/0.26" })
	}
	resolved = if !Request.body(request).is_empty() and !headers.any(|header| header.name.with_ascii_lowercased() == "content-type") {
		with_agent.append({ name: "Content-Type", value: "text/plain" })
	} else {
		with_agent
	}
	request.with_headers(resolved)
}

expect {
	request = request_with_defaults(Request.from_method(GET))
	request.headers() == [{ name: "User-Agent", value: "roc-basic-cli/0.26" }]
}
expect {
	request = request_with_defaults(Request.from_method(POST).with_body([1]))
	request.headers().contains({ name: "Content-Type", value: "text/plain" })
}
expect {
	headers = [{ name: "uSeR-aGeNt", value: "my-cli" }, { name: "content-TYPE", value: "application/custom" }]
	request_with_defaults(Request.from_method(GET).with_headers(headers)).headers() == headers
}
