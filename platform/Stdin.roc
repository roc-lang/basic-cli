interface Stdin
    exposes [line,bytes,Error]
    imports [Effect, Task.{ Task }, InternalTask]

Error : [
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
line : Task Str [StdinErr Error]
line =
    Effect.stdinLine
    |> Effect.map \res -> Result.mapErr res handleErr
    |> InternalTask.fromEffect

## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
##
## > This is typically used in combintation with [Tty.enableRawMode],
## which disables defaults terminal bevahiour and allows reading input
## without buffering until Enter key is pressed.
bytes : Task (List U8) *
bytes =
    Effect.stdinBytes
    |> Effect.map Ok
    |> InternalTask.fromEffect
