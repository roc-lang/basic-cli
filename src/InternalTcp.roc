interface InternalTcp
    exposes [ConnectErr, StreamErr, TcpResult]
    imports []

TcpResult a fail : [ Success a, Failure fail ]

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