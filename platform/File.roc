File := [].{
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

    ## Read all bytes from a file.
    read_bytes! : Str => Try(List(U8), [FileErr(IOErr)])

    ## Write bytes to a file, replacing any existing contents.
    write_bytes! : Str, List(U8) => Try({}, [FileErr(IOErr)])

    ## Read a file's contents as a UTF-8 string.
    ##
    ## If the file contains invalid UTF-8, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    read_utf8! : Str => Try(Str, [FileErr(IOErr)])

    ## Write a UTF-8 string to a file, replacing any existing contents.
    write_utf8! : Str, Str => Try({}, [FileErr(IOErr)])

    ## Delete a file.
    delete! : Str => Try({}, [FileErr(IOErr)])
}
