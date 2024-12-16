module [
    Err,
    line!,
    write!,
]

import Host

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
Err : [
    NotFound,
    PermissionDenied,
    BrokenPipe,
    AlreadyExists,
    Interrupted,
    Unsupported,
    OutOfMemory,
    Other Str,
]

handleErr : Host.InternalIOErr -> [StderrErr Err]
handleErr = \{ tag, msg } ->
    when tag is
        NotFound -> StderrErr NotFound
        PermissionDenied -> StderrErr PermissionDenied
        BrokenPipe -> StderrErr BrokenPipe
        AlreadyExists -> StderrErr AlreadyExists
        Interrupted -> StderrErr Interrupted
        Unsupported -> StderrErr Unsupported
        OutOfMemory -> StderrErr OutOfMemory
        Other | EndOfFile -> StderrErr (Other msg)

## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
## followed by a newline.
##
## > To write to `stderr` without the newline, see [Stderr.write!].
line! : Str => Result {} [StderrErr Err]
line! = \str ->
    Host.stderr_line! str
    |> Result.mapErr handleErr

## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
##
## Most terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## > To write to `stderr` with a newline at the end, see [Stderr.line!].
write! : Str => Result {} [StderrErr Err]
write! = \str ->
    Host.stderr_write! str
    |> Result.mapErr handleErr
