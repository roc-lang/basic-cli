import IOErr exposing [IOErr]

## See Stdout.roc for explanation of why hosted functions use closed error types.
host_stdin_line! : {} => Try(Str, [EndOfFile, StdinErr(IOErr)])
host_stdin_bytes! : {} => Try(List(U8), [EndOfFile, StdinErr(IOErr)])
host_stdin_read_to_end! : {} => Try(List(U8), IOErr)

Stdin := [].{
    ## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
    ##
    ## > This task will block the program from continuing until `stdin` receives a newline character
    ## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
    ## program having gotten stuck. It's often helpful to print a prompt first, so
    ## the user knows it's necessary to enter something before the program will continue.
    line! : {} => Try(Str, [EndOfFile, StdinErr(IOErr), ..])
    line! = |arg| {
        match host_stdin_line!(arg) {
            Ok(val) => Ok(val)
            Err(EndOfFile) => Err(EndOfFile)
            Err(StdinErr(ioerr)) => Err(StdinErr(ioerr))
        }
    }

    ## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
    ## This function can read no more than 16,384 bytes at a time. Use [read_to_end!] if you need more.
    ##
    ## > This is typically used in combintation with [Tty.enable_raw_mode!],
    ## which disables defaults terminal bevahiour and allows reading input
    ## without buffering until Enter key is pressed.
    bytes! : {} => Try(List(U8), [EndOfFile, StdinErr(IOErr), ..])
    bytes! = |arg| {
        match host_stdin_bytes!(arg) {
            Ok(val) => Ok(val)
            Err(EndOfFile) => Err(EndOfFile)
            Err(StdinErr(ioerr)) => Err(StdinErr(ioerr))
        }
    }

    ## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin))
    ## until [EOF](https://en.wikipedia.org/wiki/End-of-file) in this source.
    read_to_end! : {} => Try(List(U8), [StdinErr(IOErr), ..])
    read_to_end! = |arg| {
        match host_stdin_read_to_end!(arg) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StdinErr(ioerr))
        }
    }
}
