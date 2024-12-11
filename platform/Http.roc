module [
    Request,
    Method,
    Header,
    TimeoutConfig,
    Response,
    Err,
    header,
    handleStringResponse,
    defaultRequest,
    errorToString,
    errorBodyToBytes,
    send!,
    get!,
]

import InternalHttp exposing [errorBodyToUtf8, errorBodyFromUtf8]
import Host

## Represents an HTTP request.
Request : {
    method : Method,
    headers : List Header,
    url : Str,
    mimeType : Str,
    body : List U8,
    timeout : TimeoutConfig,
}

## Represents an HTTP method.
Method : InternalHttp.Method

## Represents an HTTP header e.g. `Content-Type: application/json`
Header : InternalHttp.Header

## Represents a timeout configuration for an HTTP request.
TimeoutConfig : InternalHttp.TimeoutConfig

## Represents an HTTP response.
Response : {
    url : Str,
    statusCode : U16,
    statusText : Str,
    headers : List Header,
    body : List U8,
}

## Represents an HTTP error.
Err : InternalHttp.Error

## Convert the ErrorBody of a BadStatus error to List U8.
errorBodyToBytes = errorBodyFromUtf8

## A default [Request] value.
##
## ```
## # GET "roc-lang.org"
## { Http.defaultRequest &
##     url: "https://www.roc-lang.org",
## }
## ```
##
defaultRequest : Request
defaultRequest = {
    method: Get,
    headers: [],
    url: "",
    mimeType: "",
    body: [],
    timeout: NoTimeout,
}

## An HTTP header for configuring requests.
##
## See common headers [here](https://en.wikipedia.org/wiki/List_of_HTTP_header_fields).
##
header : Str, Str -> Header
header = \key, value ->
    { key, value }

## Map a [Response] body to a [Str] or return an [Err].
handleStringResponse : Response -> Result Str Err
handleStringResponse = \response ->
    response.body
    |> Str.fromUtf8
    |> Result.mapErr \BadUtf8 _ pos ->
        position = Num.toStr pos

        BadBody "Invalid UTF-8 at byte offset $(position)"

## Convert an [Err] to a [Str].
errorToString : Err -> Str
errorToString = \err ->
    when err is
        BadRequest e -> "Invalid Request: $(e)"
        Timeout ms -> "Request timed out after $(Num.toStr ms) ms."
        NetworkError -> "Network error."
        BadStatus { code, body } ->
            when body |> errorBodyToUtf8 |> Str.fromUtf8 is
                Ok bodyStr -> "Request failed with status $(Num.toStr code): $(bodyStr)"
                Err _ -> "Request failed with status $(Num.toStr code)."

        BadBody details -> "Request failed: Invalid body: $(details)"

## Send an HTTP request, succeeds with a value of [Str] or fails with an
## [Err].
##
## ```
## # Prints out the HTML of the Roc-lang website.
## response =
##     { Http.defaultRequest & url: "https://www.roc-lang.org" }
##     |> Http.send!
##
## response.body
## |> Str.fromUtf8
## |> Result.withDefault "Invalid UTF-8"
## |> Stdout.line
## ```
send! : Request => Result Response [HttpErr Err]
send! = \req ->
    timeoutMs =
        when req.timeout is
            NoTimeout -> 0
            TimeoutMilliseconds ms -> ms

    internalRequest : InternalHttp.Request
    internalRequest = {
        method: InternalHttp.methodToStr req.method,
        headers: req.headers,
        url: req.url,
        mimeType: req.mimeType,
        body: req.body,
        timeoutMs,
    }

    # TODO: Fix our C ABI codegen so that we don't this Box.box heap allocation
    { variant, body, metadata } = Host.sendRequest! (Box.box internalRequest)

    responseResult =
        when variant is
            "Timeout" -> Err (Timeout timeoutMs)
            "NetworkErr" -> Err NetworkError
            "BadStatus" ->
                Err
                    (
                        BadStatus {
                            code: metadata.statusCode,
                            body: errorBodyFromUtf8 body,
                        }
                    )

            "GoodStatus" ->
                Ok {
                    url: metadata.url,
                    statusCode: metadata.statusCode,
                    statusText: metadata.statusText,
                    headers: metadata.headers,
                    body,
                }

            "BadRequest" | _other -> Err (BadRequest metadata.statusText)

    responseResult |> Result.mapErr HttpErr

## Try to perform an HTTP get request and convert (decode) the received bytes into a Roc type.
## Very useful for working with Json.
##
## ```
## import json.Json
##
## # On the server side we send `Encode.toBytes {foo: "Hello Json!"} Json.utf8`
## { foo } = Http.get! "http://localhost:8000" Json.utf8
## ```
get! : Str, fmt => Result body [HttpErr Http.Err, HttpDecodingFailed] where body implements Decoding, fmt implements DecoderFormatting
get! = \url, fmt ->
    response = send!? { defaultRequest & url }

    Decode.fromBytes response.body fmt
    |> Result.mapErr \_ -> HttpDecodingFailed
