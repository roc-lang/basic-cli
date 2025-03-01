module [
    IOErr,
    line!,
    write!,
    write_bytes!,
]

import Host
import InternalIOErr

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

handle_err : InternalIOErr.IOErrFromHost -> [StdoutErr IOErr]
handle_err = |{ tag, msg }|
    when tag is
        NotFound -> StdoutErr(NotFound)
        PermissionDenied -> StdoutErr(PermissionDenied)
        BrokenPipe -> StdoutErr(BrokenPipe)
        AlreadyExists -> StdoutErr(AlreadyExists)
        Interrupted -> StdoutErr(Interrupted)
        Unsupported -> StdoutErr(Unsupported)
        OutOfMemory -> StdoutErr(OutOfMemory)
        Other | EndOfFile -> StdoutErr(Other(msg))

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
## followed by a newline.
##
## > To write to `stdout` without the newline, see [Stdout.write!].
##
line! : Str => Result {} [StdoutErr IOErr]
line! = |str|
    Host.stdout_line!(str)
    |> Result.map_err(handle_err)

## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
##
## Note that many terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## > To write to `stdout` with a newline at the end, see [Stdout.line!].
write! : Str => Result {} [StdoutErr IOErr]
write! = |str|
    Host.stdout_write!(str)
    |> Result.map_err(handle_err)

write_bytes! : List U8 => Result {} [StdoutErr IOErr]
write_bytes! = |bytes|
    Host.stdout_write_bytes!(bytes)
    |> Result.map_err(handle_err)
