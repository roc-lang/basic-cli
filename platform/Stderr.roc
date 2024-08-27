module [line, write, Err]

import PlatformTasks

## **BrokenPipe** - This error can occur when writing to a stdout that is no longer connected
## to a valid input. For example, if the process on the receiving end of a pipe closes its
## end, any write to that pipe could lead to a BrokenPipe error.
##
## **WouldBlock** - This error might occur if stdout is set to non-blocking mode and the write
## operation would block because the output buffer is full.
##
## **WriteZero** - This indicates an attempt to write "zero" bytes which is technically a no-operation
## (no-op), but if detected, it could be raised as an error.
##
## **Unsupported** - If the stdout operation involves writing data in a manner or format that is not
## supported, this error could be raised.
##
## **Interrupted** - This can happen if a signal interrupts the writing process before it completes.
##
## **OutOfMemory** - This could occur if there is not enough memory available to buffer the data being
## written to stdout.
##
## **Other** - This is a catch-all for any error not specifically categorized by the other ErrorKind
## variants.
Err : [
    BrokenPipe,
    WouldBlock,
    WriteZero,
    Unsupported,
    Interrupted,
    OutOfMemory,
    Other Str,
]

handleErr = \err ->
    when err is
        e if e == "ErrorKind::BrokenPipe" -> StderrErr BrokenPipe
        e if e == "ErrorKind::WouldBlock" -> StderrErr WouldBlock
        e if e == "ErrorKind::WriteZero" -> StderrErr WriteZero
        e if e == "ErrorKind::Unsupported" -> StderrErr Unsupported
        e if e == "ErrorKind::Interrupted" -> StderrErr Interrupted
        e if e == "ErrorKind::OutOfMemory" -> StderrErr OutOfMemory
        str -> StderrErr (Other str)

## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
## followed by a newline.
##
## > To write to `stderr` without the newline, see [Stderr.write].
line : Str -> Task {} [StderrErr Err]
line = \str ->
    PlatformTasks.stderrLine str
    |> Task.mapErr handleErr

## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
##
## Most terminals will not actually display strings that are written to them until they receive a newline,
## so this may appear to do nothing until you write a newline!
##
## > To write to `stderr` with a newline at the end, see [Stderr.line].
write : Str -> Task {} [StderrErr Err]
write = \str ->
    PlatformTasks.stderrWrite str
    |> Task.mapErr handleErr
