module [
    Request,
    Response,
    Method,
    Header,
    header,
    default_request,
    send!,
    get!,
    get_utf8!,
]

import InternalHttp
import Host

## Represents an HTTP method: `[OPTIONS, GET, POST, PUT, DELETE, HEAD, TRACE, CONNECT, PATCH, EXTENSION Str]`
Method : InternalHttp.Method

## Represents an HTTP header e.g. `Content-Type: application/json`.
## Header is a `{ name : Str, value : Str }`.
Header : InternalHttp.Header

## Represents an HTTP request.
## Request is a record:
## ```
## {
##    method : Method,
##    headers : List Header,
##    uri : Str,
##    body : List U8,
##    timeout_ms : [TimeoutMilliseconds U64, NoTimeout],
## }
## ```
Request : InternalHttp.Request

## Represents an HTTP response.
##
## Response is a record with the following fields:
## ```
## {
##     status : U16,
##     headers : List Header,
##     body : List U8
## }
## ```
Response : InternalHttp.Response

## A default [Request] value with the following values:
## ```
## {
##     method: GET
##     headers: []
##     uri: ""
##     body: []
##     timeout_ms: NoTimeout
## }
## ```
##
## Example:
## ```
## # GET "roc-lang.org"
## { Http.default_request &
##     uri: "https://www.roc-lang.org",
## }
## ```
##
default_request : Request
default_request = {
    method: GET,
    headers: [],
    uri: "",
    body: [],
    timeout_ms: NoTimeout,
}

## An HTTP header for configuring requests.
##
## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
##
## Example: `header(("Content-Type", "application/json"))`
##
header : (Str, Str) -> Header
header = |(name, value)| { name, value }

## Send an HTTP request, succeeds with a [Response] or fails with a [HttpErr _].
##
## ```
## # Prints out the HTML of the Roc-lang website.
## response : Response
## response =
##     Http.send!({ Http.default_request & uri: "https://www.roc-lang.org" })?
##
## Stdout.line!(Str.from_utf8(response.body))?
## ```
send! : Request => Result Response [HttpErr [Timeout, NetworkError, BadBody, Other (List U8)]]
send! = |request|

    host_request = InternalHttp.to_host_request(request)

    response = Host.send_request!(host_request) |> InternalHttp.from_host_response

    other_error_prefix = Str.to_utf8("OTHER ERROR\n")

    if response.status == 408 and response.body == Str.to_utf8("Request Timeout") then
        Err(HttpErr(Timeout))
    else if response.status == 500 and response.body == Str.to_utf8("Network Error") then
        Err(HttpErr(NetworkError))
    else if response.status == 500 and response.body == Str.to_utf8("Bad Body") then
        Err(HttpErr(BadBody))
    else if response.status == 500 and List.starts_with(response.body, other_error_prefix) then
        Err(HttpErr(Other(List.drop_first(response.body, List.len(other_error_prefix)))))
    else
        Ok(response)

## Try to perform an HTTP get request and convert (decode) the received bytes into a Roc type.
## Very useful for working with Json.
##
## ```
## import json.Json
##
## # On the server side we send `Encode.to_bytes({foo: "Hello Json!"}, Json.utf8)`
## { foo } = Http.get!("http://localhost:8000", Json.utf8)?
## ```
get! : Str, fmt => Result body [HttpDecodingFailed, HttpErr _] where body implements Decoding, fmt implements DecoderFormatting
get! = |uri, fmt|
    response = send!({ default_request & uri })?

    Decode.from_bytes(response.body, fmt)
    |> Result.map_err(|_| HttpDecodingFailed)

# Contributor note: Trying to use BadUtf8 { problem : Str.Utf8Problem, index : U64 } in the error here results in a "Alias `6.IdentId(11)` not registered in delayed aliases!".
## Try to perform an HTTP get request and convert the received bytes (in the body) into a UTF-8 string.
##
## ```
## # On the server side we, send `Str.to_utf8("Hello utf8")`
##
## hello_str : Str
## hello_str = Http.get_utf8!("http://localhost:8000")?
## ```
get_utf8! : Str => Result Str [BadBody Str, HttpErr _]
get_utf8! = |uri|
    response = send!({ default_request & uri })?

    response.body
    |> Str.from_utf8
    |> Result.map_err(|err| BadBody("Error in get_utf8!: failed to convert received body bytes into utf8:\n\t${Inspect.to_str(err)}"))
