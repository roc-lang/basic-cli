module [
    Err,
    line!,
    bytes!,
    readToEnd!,
]

import PlatformTasks

## **EndOfFile** - This error occurs when an end-of-file (EOF) condition is met unexpectedly
## during input operations. Typically indicates that no more data is available for reading.
##
## **BrokenPipe** - This error happens when an attempt to write to a pipe cannot proceed because
## the other end of the pipe has been closed. Common in IPC (Inter-Process Communication) scenarios.
##
## **UnexpectedEof** - Similar to EndOfFile but specifically refers to cases where the EOF occurs
## unexpectedly, possibly indicating truncated or corrupted data streams.
##
## **InvalidInput** - This error is raised when an input operation receives data that is not in a
## valid format, suggesting possible data corruption or a mismatch in expected data format.
##
## **OutOfMemory** - Occurs when an operation fails due to insufficient memory available to
## complete the operation. This can affect data reading, buffering, or processing.
##
## **Interrupted** - This error can happen if an input operation is interrupted by a system
## signal before it could complete, often needing a retry or causing the operation to fail.
##
## **Unsupported** - Raised when an operation involves a feature or operation mode that is not
## supported. This might involve character encodings, data compression formats, etc.
##
## **Other** - A catch-all category for errors that do not fall into the specified categories.
## Allows for flexible error handling of uncommon or unexpected conditions.
Err : [
    EndOfFile,
    BrokenPipe,
    UnexpectedEof,
    InvalidInput,
    OutOfMemory,
    Interrupted,
    Unsupported,
    Other Str,
]

handleErr = \err ->
    when err is
        e if e == "EOF" -> StdinErr EndOfFile
        e if e == "ErrorKind::BrokenPipe" -> StdinErr BrokenPipe
        e if e == "ErrorKind::UnexpectedEof" -> StdinErr UnexpectedEof
        e if e == "ErrorKind::InvalidInput" -> StdinErr InvalidInput
        e if e == "ErrorKind::OutOfMemory" -> StdinErr OutOfMemory
        e if e == "ErrorKind::Interrupted" -> StdinErr Interrupted
        e if e == "ErrorKind::Unsupported" -> StdinErr Unsupported
        str -> StdinErr (Other str)

## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
##
## > This task will block the program from continuing until `stdin` receives a newline character
## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
## programming having gotten stuck. It's often helpful to print a prompt first, so
## the user knows it's necessary to enter something before the program will continue.
line! : {} => Result Str [StdinErr Err]
line! = \{} ->
    PlatformTasks.stdinLine! {}
    |> Result.mapErr handleErr

## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
## ‼️ This function can read no more than 256 bytes at a time. Use [readToEnd] if you need more.
##
## > This is typically used in combintation with [Tty.enableRawMode],
## which disables defaults terminal bevahiour and allows reading input
## without buffering until Enter key is pressed.
bytes! : {} => List U8
bytes! = \{} ->
    # will return an empty list if no bytes are available
    PlatformTasks.stdinBytes! {}

## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) until EOF in this source.
readToEnd! : {} => Result (List U8) [StdinErr Err]
readToEnd! = \{} ->
    PlatformTasks.stdinReadToEnd!
    |> Result.mapErr \internalErr ->
        when internalErr.tag is
            BrokenPipe -> StdinErr BrokenPipe
            WouldBlock -> StdinErr (Other "WouldBlock")
            WriteZero -> StdinErr (Other "WriteZero")
            Unsupported -> StdinErr Unsupported
            Interrupted -> StdinErr Interrupted
            OutOfMemory -> StdinErr OutOfMemory
            UnexpectedEof -> StdinErr UnexpectedEof
            InvalidInput -> StdinErr InvalidInput
            Other -> StdinErr (Other internalErr.msg)
