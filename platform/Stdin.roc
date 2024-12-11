module [
    Err,
    line!,
    bytes!,
    readToEnd!,
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

handleErr : Host.InternalIOErr -> [EndOfFile, StdinErr Err]
handleErr = \{ tag, msg } ->
    when tag is
        NotFound -> StdinErr NotFound
        PermissionDenied -> StdinErr PermissionDenied
        BrokenPipe -> StdinErr BrokenPipe
        AlreadyExists -> StdinErr AlreadyExists
        Interrupted -> StdinErr Interrupted
        Unsupported -> StdinErr Unsupported
        OutOfMemory -> StdinErr OutOfMemory
        EndOfFile -> EndOfFile
        Other -> StdinErr (Other msg)

## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
##
## > This task will block the program from continuing until `stdin` receives a newline character
## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
## programming having gotten stuck. It's often helpful to print a prompt first, so
## the user knows it's necessary to enter something before the program will continue.
line! : {} => Result Str [EndOfFile, StdinErr Err]
line! = \{} ->
    Host.stdinLine! {}
    |> Result.mapErr handleErr

## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
## ‼️ This function can read no more than 16,384 bytes at a time. Use [readToEnd!] if you need more.
##
## > This is typically used in combintation with [Tty.enableRawMode!],
## which disables defaults terminal bevahiour and allows reading input
## without buffering until Enter key is pressed.
bytes! : {} => Result (List U8) [EndOfFile, StdinErr Err]
bytes! = \{} ->
    Host.stdinBytes! {}
    |> Result.mapErr handleErr

## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) until EOF in this source.
readToEnd! : {} => Result (List U8) [StdinErr Err]
readToEnd! = \{} ->
    Host.stdinReadToEnd! {}
    |> Result.mapErr \{ tag, msg } ->
        when tag is
            NotFound -> StdinErr NotFound
            PermissionDenied -> StdinErr PermissionDenied
            BrokenPipe -> StdinErr BrokenPipe
            AlreadyExists -> StdinErr AlreadyExists
            Interrupted -> StdinErr Interrupted
            Unsupported -> StdinErr Unsupported
            OutOfMemory -> StdinErr OutOfMemory
            EndOfFile -> crash "unreachable, reading to EOF"
            Other -> StdinErr (Other msg)
