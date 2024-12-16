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

Response : {
    status : U16,
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
    status,
    headers,
    body,
}

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
    status,
    headers,
    body,
}
