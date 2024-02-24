interface Http
    exposes [
        Request,
        Method,
        Header,
        TimeoutConfig,
        Response,
        Metadata,
        Error,
        header,
        handleStringResponse,
        defaultRequest,
        errorToString,
        send,
    ]
    imports [Effect, InternalTask, Task.{ Task }, InternalHttp]

## Represents an HTTP request.
Request : InternalHttp.Request

## Represents an HTTP method.
Method : InternalHttp.Method

## Represents an HTTP header e.g. `Content-Type: application/json`
Header : InternalHttp.Header

## Represents a timeout configuration for an HTTP request.
TimeoutConfig : InternalHttp.TimeoutConfig

## Represents an HTTP response.
Response : InternalHttp.Response

## Represents HTTP metadata, such as the URL or status code.
Metadata : InternalHttp.Metadata

## Represents an HTTP error.
Error : InternalHttp.Error

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
header =
    Header

## Map a [Response] body to a [Str] or return an [Error].
handleStringResponse : Response -> Result Str Error
handleStringResponse = \response ->
    when response is
        BadRequest err -> Err (BadRequest err)
        Timeout ms -> Err (Timeout ms)
        NetworkError -> Err NetworkError
        BadStatus metadata _ -> Err (BadStatus metadata.statusCode)
        GoodStatus _ bodyBytes ->
            Str.fromUtf8 bodyBytes
            |> Result.mapErr
                \BadUtf8 _ pos ->
                    position = Num.toStr pos

                    BadBody "Invalid UTF-8 at byte offset $(position)"

## Convert an [Error] to a [Str].
errorToString : Error -> Str
errorToString = \err ->
    when err is
        BadRequest e -> "Invalid Request: $(e)"
        Timeout ms -> "Request timed out ($(Num.toStr ms)ms)"
        NetworkError -> "Network error"
        BadStatus code -> Str.concat "Request failed with status " (Num.toStr code)
        BadBody details -> Str.concat "Request failed. Invalid body. " details

## Task to send an HTTP request, succeeds with a value of [Str] or fails with an
## [Error].
##
## ```
## # Prints out the HTML of the Roc-lang website.
## result <-
##     { Http.defaultRequest &
##         url: "https://www.roc-lang.org",
##     }
##     |> Http.send
##     |> Task.attempt
##
## when result is
##     Ok responseBody -> Stdout.line responseBody
##     Err _ -> Stdout.line "Oops, something went wrong!"
## ```
send : Request -> Task Str Error
send = \req ->
    # TODO: Fix our C ABI codegen so that we don't this Box.box heap allocation
    Effect.sendRequest (Box.box req)
    |> Effect.map handleStringResponse
    |> InternalTask.fromEffect
