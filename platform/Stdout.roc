import IOErr exposing [IOErr]

## These hosted functions return Try({}, IOErr) directly - matching the host's ABI.
## They must NOT use open tag unions ([..]) because the compiler would extend them
## with error variants from the calling context, changing the memory layout and
## causing a mismatch with what the host actually writes.
host_stdout_line! : Str => Try({}, IOErr)
host_stdout_write! : Str => Try({}, IOErr)
host_stdout_write_bytes! : List(U8) => Try({}, IOErr)

Stdout := [].{
    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
    ## followed by a newline.
    ##
    ## > To write to `stdout` without the newline, see [Stdout.write!].
    line! : Str => Try({}, [StdoutErr(IOErr), ..])
    line! = |msg| {
        match host_stdout_line!(msg) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StdoutErr(ioerr))
        }
    }

    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    ##
    ## Note that many terminals will not actually display strings that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    ##
    ## > To write to `stdout` with a newline at the end, see [Stdout.line!].
    write! : Str => Try({}, [StdoutErr(IOErr), ..])
    write! = |msg| {
        match host_stdout_write!(msg) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StdoutErr(ioerr))
        }
    }

    ## Write the given bytes to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    ##
    ## Note that many terminals will not actually display content that is written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    write_bytes! : List(U8) => Try({}, [StdoutErr(IOErr), ..])
    write_bytes! = |bytes| {
        match host_stdout_write_bytes!(bytes) {
            Ok(val) => Ok(val)
            Err(ioerr) => Err(StdoutErr(ioerr))
        }
    }
}
