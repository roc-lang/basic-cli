module [
    Socket,
    SocketErr,
    BindErr,
    BindResult,
    ReceiveResult,
    fromBindResult,
    fromReceiveResult,
]

Socket := U64

SocketErr : [
    Nope,
]

BindErr : [
    Nope,
]

BindResult : [
    Bound Socket,
    Error BindErr,
]

fromBindResult : BindResult -> Result Socket BindErr
fromBindResult = \result ->
    when result is
        Bound socket ->
            Ok socket

        Error err ->
            Err err

ReceiveResult : [
    Received (List U8),
    Error SocketErr,
]

fromReceiveResult : ReceiveResult -> Result (List U8) SocketErr
fromReceiveResult = \result ->
    when result is
        Received bytes ->
            Ok bytes

        Error err ->
            Err err
