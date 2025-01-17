module [
    IOErr,
    IOErrFromHost,
    handle_err,
]

## **NotFound** - An entity was not found, often a file.
##
## **PermissionDenied** - The operation lacked the necessary privileges to complete.
##
## **BrokenPipe** - The operation failed because a pipe was closed.
##
## **AlreadyExists** - An entity already exists, often a file.
##
## **Interrupted** - This operation was interrupted. Interrupted operations can typically be retried.
##
## **Unsupported** - This operation is unsupported on this platform. This means that the operation can never succeed.
##
## **OutOfMemory** - An operation could not be completed, because it failed to allocate enough memory.
##
## **Other** - A custom error that does not fall under any other I/O error kind.
IOErr : [
    NotFound,
    PermissionDenied,
    BrokenPipe,
    AlreadyExists,
    Interrupted,
    Unsupported,
    OutOfMemory,
    Other Str,
]

IOErrFromHost : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

handle_err : IOErrFromHost -> IOErr
handle_err = |{ tag, msg }|
    when tag is
        NotFound -> NotFound
        PermissionDenied -> PermissionDenied
        BrokenPipe -> BrokenPipe
        AlreadyExists -> AlreadyExists
        Interrupted -> Interrupted
        Unsupported -> Unsupported
        OutOfMemory -> OutOfMemory
        Other | EndOfFile -> Other(msg)
