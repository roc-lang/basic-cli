import IOErr exposing [IOErr]

Stderr := [].{
    ## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)),
    ## followed by a newline.
    ##
    ## > To write to `stderr` without the newline, see [Stderr.write!].
    line! : Str => Try({}, [StderrErr(IOErr), ..])

    ## Write the given string to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
    ##
    ## Most terminals will not actually display strings that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    ##
    ## > To write to `stderr` with a newline at the end, see [Stderr.line!].
    write! : Str => Try({}, [StderrErr(IOErr), ..])

    ## Write the given bytes to [standard error](https://en.wikipedia.org/wiki/Standard_streams#Standard_error_(stderr)).
    ##
    ## Most terminals will not actually display content that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    write_bytes! : List(U8) => Try({}, [StderrErr(IOErr), ..])
}
