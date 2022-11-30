interface InternalFile
    exposes [ReadErr, ReadUtf8Err, WriteErr, ReadProblem, WriteProblem]
    imports [Path.{ Path }]

ReadUtf8Err : [FileReadErr Path ReadProblem, FileReadUtf8Err Path Str.Utf8Problem]

ReadErr : [FileReadErr Path ReadProblem]

ReadProblem : [
    NotFound,
    Interrupted,
    InvalidFilename,
    PermissionDenied,
    TooManySymlinks, # aka FilesystemLoop
    TooManyHardlinks,
    TimedOut,
    StaleNetworkFileHandle,
    OutOfMemory,
    Unsupported,
    Unrecognized I32 Str,
]

WriteErr : [FileWriteErr Path WriteProblem]

WriteProblem : [
    NotFound,
    Interrupted,
    InvalidFilename,
    PermissionDenied,
    TooManySymlinks, # aka FilesystemLoop
    TooManyHardlinks,
    TimedOut,
    StaleNetworkFileHandle,
    ReadOnlyFilesystem,
    AlreadyExists, # can this happen here?
    WasADirectory,
    WriteZero, # TODO come up with a better name for this, or roll it into another error tag
    StorageFull,
    FilesystemQuotaExceeded, # can this be combined with StorageFull?
    FileTooLarge,
    ResourceBusy,
    ExecutableFileBusy,
    OutOfMemory,
    Unsupported,
    Unrecognized I32 Str,
]

# DirReadErr : [
#     NotFound,
#     Interrupted,
#     InvalidFilename,
#     PermissionDenied,
#     TooManySymlinks, # aka FilesystemLoop
#     TooManyHardlinks,
#     TimedOut,
#     StaleNetworkFileHandle,
#     NotADirectory,
#     OutOfMemory,
#     Unsupported,
#     Unrecognized I32 Str,
# ]
# RmDirError : [
#     NotFound,
#     Interrupted,
#     InvalidFilename,
#     PermissionDenied,
#     TooManySymlinks, # aka FilesystemLoop
#     TooManyHardlinks,
#     TimedOut,
#     StaleNetworkFileHandle,
#     NotADirectory,
#     ReadOnlyFilesystem,
#     DirectoryNotEmpty,
#     OutOfMemory,
#     Unsupported,
#     Unrecognized I32 Str,
# ]
