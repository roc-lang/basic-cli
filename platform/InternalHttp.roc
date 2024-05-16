module [Request, Method, Header, TimeoutConfig, Part, InternalResponse, Error]

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
    BadStatus { code: U16, body: List U8 },
    BadBody Str,
]
