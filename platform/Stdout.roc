Stdout := [].{
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
    IOErr := [
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other(Str),
    ]

    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)),
    ## followed by a newline.
    ##
    ## > To write to `stdout` without the newline, see [Stdout.write!].
    line! : Str => {}

    ## Write the given string to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    ##
    ## Note that many terminals will not actually display strings that are written to them until they receive a newline,
    ## so this may appear to do nothing until you write a newline!
    ##
    ## > To write to `stdout` with a newline at the end, see [Stdout.line!].
    write! : Str => {}

    # ## Write the given bytes to [standard output](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)).
    # ##
    # ## Note that many terminals will not actually display content that is written to them until they receive a newline,
    # ## so this may appear to do nothing until you write a newline!
    # write_bytes! : List(U8) => {}
}
