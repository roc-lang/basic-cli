interface InternalTcp
    exposes [ConnectErr, StreamErr, TcpResult, toResult]
    imports []

TcpResult a fail : [Success a, Failure fail]

toResult : TcpResult a fail -> Result a fail
toResult = \result ->
    when result is
        Success value ->
            Ok value

        Failure fail ->
            Err fail

ConnectErr : [
    PermissionDenied,
    AddrInUse,
    AddrNotAvailable,
    ConnectionRefused,
    Interrupted,
    NetworkUnreachable,
    NetworkDown,
    TimedOut,
    Unsupported,
    Unrecognized I32 Str,
]

StreamErr : [
    PermissionDenied,
    ConnectionRefused,
    ConnectionReset,
    Interrupted,
    OutOfMemory,
    BrokenPipe,
    Unrecognized I32 Str,
]
