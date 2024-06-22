module [Request, Method, Header, TimeoutConfig, Part, InternalResponse, Error, ErrorBody, errorBodyToUtf8, errorBodyFromUtf8]

Request : {
    method : Method,
    headers : List Header,
    url : Str,
    mimeType : Str,
    body : List U8,
    timeout : TimeoutConfig,
}

Method : [Options, Get, Post, Put, Delete, Head, Trace, Connect, Patch]

Header : [Header Str Str]

# Name is distinguished from the Timeout tag used in Response and Error
TimeoutConfig : [TimeoutMilliseconds U64, NoTimeout]

Part : [Part Str (List U8)]

InternalResponse : [
    BadRequest Str,
    Timeout U64,
    NetworkError,
    BadStatus Metadata (List U8),
    GoodStatus Metadata (List U8),
]

Metadata : {
    url : Str,
    statusCode : U16,
    statusText : Str,
    headers : List Header,
}

Error : [
    BadRequest Str,
    Timeout U64,
    NetworkError,
    BadStatus { code : U16, body : ErrorBody },
    BadBody Str,
]

ErrorBody := List U8 implements [
        Inspect {
            toInspector: errorBodyToInspector,
        },
    ]

errorBodyToInspector : ErrorBody -> _
errorBodyToInspector = \@ErrorBody val ->
    fmt <- Inspect.custom
    when val |> List.takeFirst 50 |> Str.fromUtf8 is
        Ok str -> Inspect.apply (Inspect.str str) fmt
        Err _ -> Inspect.apply (Inspect.str "Invalid UTF-8 data") fmt

errorBodyToUtf8 : ErrorBody -> List U8
errorBodyToUtf8 = \@ErrorBody body -> body

errorBodyFromUtf8 : List U8 -> ErrorBody
errorBodyFromUtf8 = \body -> @ErrorBody body
