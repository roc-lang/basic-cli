module [
    ReadErr,
    handleReadErr,
    WriteErr,
    handleWriteErr,
]

## Tag union of possible errors when reading a file or directory.
ReadErr : [
    Interrupted,
    NotFound,
    OutOfMemory,
    PermissionDenied,
    TimedOut,
    Other Str,
]

handleReadErr : Str -> ReadErr
handleReadErr = \err ->
    when err is
        e if e == "ErrorKind::Interrupted" -> Interrupted
        e if e == "ErrorKind::NotFound" -> NotFound
        e if e == "ErrorKind::OutOfMemory" -> OutOfMemory
        e if e == "ErrorKind::PermissionDenied" -> PermissionDenied
        e if e == "ErrorKind::TimedOut" -> TimedOut
        str -> Other str

## Tag union of possible errors when writing a file or directory.
WriteErr : [
    NotFound,
    AlreadyExists,
    Interrupted,
    OutOfMemory,
    PermissionDenied,
    TimedOut,
    WriteZero,
    Other Str,
]

handleWriteErr : Str -> WriteErr
handleWriteErr = \err ->
    when err is
        e if e == "ErrorKind::NotFound" -> NotFound
        e if e == "ErrorKind::AlreadyExists" -> AlreadyExists
        e if e == "ErrorKind::Interrupted" -> Interrupted
        e if e == "ErrorKind::OutOfMemory" -> OutOfMemory
        e if e == "ErrorKind::PermissionDenied" -> PermissionDenied
        e if e == "ErrorKind::TimedOut" -> TimedOut
        e if e == "ErrorKind::WriteZero" -> WriteZero
        str -> Other str
