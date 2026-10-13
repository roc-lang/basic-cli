import http.Header
import http.Method
import http.Request
import http.Response
import Resource

## Define host-ABI HTTP types and convert them to the shared HTTP package types.
## These records map directly to the generated Rust glue types.
InternalHttp :: [].{

	## Errors raised by the host while sending a request, before a real HTTP
	## response is available.
	TransportErr : [Timeout, NetworkError, BadBody, Other(List(U8))]

	# Generated Rust glue uses tuple headers at the host ABI boundary.
	HostHeaderTuple : (Str, Str)

	RequestToAndFromHost : {
		method : U8,
		method_ext : Str,
		headers : List(HostHeaderTuple),
		uri : Str,
		body : List(U8),
		timeout_ms : U64,
	}

	ResponseToAndFromHost : {
		status : U16,
		headers : List(HostHeaderTuple),
		body : List(U8),
	}

	# What the host returns once the status and headers of a streaming
	# response have arrived. The body stays in the host, behind `body`.
	StreamingResponseFromHost : {
		status : U16,
		headers : List(HostHeaderTuple),
		content_length : [Known(U64), Unknown],
		body : Resource.HttpResponse,
	}

	to_host_request : Request -> RequestToAndFromHost
	to_host_request = |request| {
		method = Request.method(request)
		{
			method: to_host_method(method),
			method_ext: to_host_method_ext(method),
			headers: to_host_headers(Request.headers(request)),
			uri: Request.uri(request),
			body: Request.body(request),
			timeout_ms: to_host_timeout(Request.timeout(request)),
		}
	}

	from_host_response : ResponseToAndFromHost -> Response
	from_host_response = |response|
		Response.from_status(response.status)
			.with_headers(from_host_headers(response.headers))
			.with_body(response.body)

	to_host_headers : List(Header.Header) -> List(HostHeaderTuple)
	to_host_headers = |headers|
		headers.map(|{ name, value }| (name, value))

	from_host_headers : List(HostHeaderTuple) -> List(Header.Header)
	from_host_headers = |headers|
		headers.map(|(name, value)| { name, value })
}

to_host_method : Method.Method -> U8
to_host_method = |method|
	match method {
		OPTIONS => 5
		GET => 3
		POST => 7
		PUT => 8
		DELETE => 1
		HEAD => 4
		TRACE => 9
		CONNECT => 0
		PATCH => 6
		QUERY => 2
		Unknown(_) => 2
	}

to_host_method_ext : Method.Method -> Str
to_host_method_ext = |method|
	match method {
		QUERY => "QUERY"
		Unknown(ext) => ext
		_ => ""
	}

to_host_timeout : [TimeoutMilliseconds(U64), NoTimeout] -> U64
to_host_timeout = |timeout|
	match timeout {
		TimeoutMilliseconds(ms) => ms
		NoTimeout => 0
	}
