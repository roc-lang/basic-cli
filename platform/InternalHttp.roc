# TODO we should be able to pull this out into a cross-platform package so multiple
# platforms can use it.
#
# I haven't tried that here because I just want to get the implementation working on
# both basic-cli and basic-webserver. Copy-pase is fine for now.
module [
    Request,
    Response,
    RequestToAndFromHost,
    ResponseToAndFromHost,
    Method,
    Header,
    to_host_request,
    to_host_response,
    from_host_request,
    from_host_response,
]

# FOR ROC

# https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
Method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension Str]

# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers
Header : { name : Str, value : Str }

Request : {
    method : Method,
    headers : List Header,
    uri : Str,
    body : List U8,
    timeout_ms : [TimeoutMilliseconds U64, NoTimeout],
}

Status : [
    Success [Ok, Created, NoContent, Other U16],
    Redirect [MovedPermanently, Found, NotModified, Other U16],
    ClientErr [BadRequest, Unauthorized, Forbidden, NotFound, TooManyRequests, Other U16],
    ServerErr [InternalServerError, BadGateway, ServiceUnavailable, GatewayTimeout, Other U16],
]

Response : {
    status : Status,
    headers : List Header,
    body : List U8,
}

# FOR HOST

RequestToAndFromHost : {
    method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension],
    method_ext : Str,
    headers : List Header,
    uri : Str,
    body : List U8,
    timeout_ms : U64,
}

ResponseToAndFromHost : {
    status : U16,
    headers : List Header,
    body : List U8,
}

to_host_response : Response -> ResponseToAndFromHost
to_host_response = \{ status, headers, body } -> {
    status: to_host_status status,
    headers,
    body,
}

to_host_status : Status -> U16
to_host_status = \status ->
    when status is
        Success Ok -> 200
        Success Created -> 201
        Success NoContent -> 204
        Redirect MovedPermanently -> 301
        Redirect Found -> 302
        Redirect NotModified -> 304
        ClientErr BadRequest -> 400
        ClientErr Unauthorized -> 401
        ClientErr Forbidden -> 403
        ClientErr NotFound -> 404
        ClientErr TooManyRequests -> 429
        ServerErr InternalServerError -> 500
        ServerErr BadGateway -> 502
        ServerErr ServiceUnavailable -> 503
        ServerErr GatewayTimeout -> 504
        Success (Other code) -> code
        Redirect (Other code) -> code
        ClientErr (Other code) -> code
        ServerErr (Other code) -> code

to_host_request : Request -> RequestToAndFromHost
to_host_request = \{ method, headers, uri, body, timeout_ms } -> {
    method: to_host_method method,
    method_ext: to_host_method_ext method,
    headers,
    uri,
    body,
    timeout_ms: to_host_timeout timeout_ms,
}

to_host_method : Method -> _
to_host_method = \method ->
    when method is
        Options -> Options
        Get -> Get
        Post -> Post
        Put -> Put
        Delete -> Delete
        Head -> Head
        Trace -> Trace
        Connect -> Connect
        Patch -> Patch
        Extension _ -> Extension

to_host_method_ext : Method -> Str
to_host_method_ext = \method ->
    when method is
        Extension ext -> ext
        _ -> ""

to_host_timeout : _ -> U64
to_host_timeout = \timeout ->
    when timeout is
        TimeoutMilliseconds ms -> ms
        NoTimeout -> 0

from_host_request : RequestToAndFromHost -> Request
from_host_request = \{ method, method_ext, headers, uri, body, timeout_ms } -> {
    method: from_host_method method method_ext,
    headers,
    uri,
    body,
    timeout_ms: from_host_timeout timeout_ms,
}

from_host_method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch, Extension], Str -> Method
from_host_method = \tag, ext ->
    when tag is
        Options -> Options
        Get -> Get
        Post -> Post
        Put -> Put
        Delete -> Delete
        Head -> Head
        Trace -> Trace
        Connect -> Connect
        Patch -> Patch
        Extension -> Extension ext

from_host_timeout : U64 -> [TimeoutMilliseconds U64, NoTimeout]
from_host_timeout = \timeout ->
    when timeout is
        0 -> NoTimeout
        _ -> TimeoutMilliseconds timeout

expect from_host_timeout 0 == NoTimeout
expect from_host_timeout 1 == TimeoutMilliseconds 1

from_host_response : ResponseToAndFromHost -> Response
from_host_response = \{ status, headers, body } -> {
    status: from_host_status status,
    headers,
    body,
}

from_host_status : U16 -> Status
from_host_status = \status ->
    when status is
        200 -> Success Ok
        201 -> Success Created
        204 -> Success NoContent
        301 -> Redirect MovedPermanently
        302 -> Redirect Found
        304 -> Redirect NotModified
        400 -> ClientErr BadRequest
        401 -> ClientErr Unauthorized
        403 -> ClientErr Forbidden
        404 -> ClientErr NotFound
        429 -> ClientErr TooManyRequests
        500 -> ServerErr InternalServerError
        502 -> ServerErr BadGateway
        503 -> ServerErr ServiceUnavailable
        504 -> ServerErr GatewayTimeout
        code if code >= 200 && code < 300 -> Success (Other code)
        code if code >= 300 && code < 400 -> Redirect (Other code)
        code if code >= 400 && code < 500 -> ClientErr (Other code)
        code if code >= 500 && code < 600 -> ServerErr (Other code)
        _ -> crash "invalid HTTP status from host"

expect from_host_status 200 == Success Ok
expect from_host_status 201 == Success Created
expect from_host_status 204 == Success NoContent
expect from_host_status 301 == Redirect MovedPermanently
expect from_host_status 302 == Redirect Found
expect from_host_status 304 == Redirect NotModified
expect from_host_status 400 == ClientErr BadRequest
expect from_host_status 401 == ClientErr Unauthorized
expect from_host_status 403 == ClientErr Forbidden
expect from_host_status 404 == ClientErr NotFound
expect from_host_status 429 == ClientErr TooManyRequests
expect from_host_status 500 == ServerErr InternalServerError
expect from_host_status 502 == ServerErr BadGateway
expect from_host_status 503 == ServerErr ServiceUnavailable
expect from_host_status 504 == ServerErr GatewayTimeout
expect from_host_status 599 == ServerErr (Other 599)
