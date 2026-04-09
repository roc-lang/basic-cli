import IOErr exposing [IOErr]

## See Stdout.roc for explanation of why hosted functions use IOErr directly.
host_stderr_line! : Str => Try({}, IOErr)
host_stderr_write! : Str => Try({}, IOErr)
host_stderr_write_bytes! : List(U8) => Try({}, IOErr)

Stderr := [].{
    ## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
    ## followed by a newline.
    ##
    ## > To write to `stderr` without the newline, see [Stderr.write!].
    line! : Str => Try({}, [StderrErr(IOErr), ..])
    line! = |msg| {
        match host_stderr_line!(msg) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StderrErr(ioerr))
        }
    }

    ## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
    ##
    ## Most terminals will not actually display strings that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    ##
    ## > To write to `stderr` with a newline at the end, see [Stderr.line!].
    write! : Str => Try({}, [StderrErr(IOErr), ..])
    write! = |msg| {
        match host_stderr_write!(msg) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StderrErr(ioerr))
        }
    }

    ## Write the given bytes to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
    ##
    ## Most terminals will not actually display content that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    write_bytes! : List(U8) => Try({}, [StderrErr(IOErr), ..])
    write_bytes! = |bytes| {
        match host_stderr_write_bytes!(bytes) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StderrErr(ioerr))
        }
    }
}
