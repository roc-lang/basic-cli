Stdin := [].{
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

    ## Read a line from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
    ##
    ## > This task will block the program from continuing until `stdin` receives a newline character
    ## (e.g. because the user pressed Enter in the terminal), so using it can result in the appearance of the
    ## program having gotten stuck. It's often helpful to print a prompt first, so
    ## the user knows it's necessary to enter something before the program will continue.
    line! : {} => Str

    # ## Read bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)).
    # ## This function can read no more than 16,384 bytes at a time. Use [read_to_end!] if you need more.
    # ##
    # ## > This is typically used in combintation with [Tty.enable_raw_mode!],
    # ## which disables defaults terminal bevahiour and allows reading input
    # ## without buffering until Enter key is pressed.
    # bytes! : {} => List(U8)

    # ## Read all bytes from [standard input](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin))
    # ## until [EOF](https://en.wikipedia.org/wiki/End-of-file) in this source.
    # read_to_end! : {} => List(U8)
}
