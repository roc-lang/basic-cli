Path := [].{
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
    ## **Unsupported** - This operation is unsupported on this platform.
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

    ## Returns `Bool.true` if the path exists on disk and is pointing at a regular file.
    ##
    ## This function will traverse symbolic links to query information about the
    ## destination file. In case of broken symbolic links this will return `Bool.false`.
    is_file! : Str => Try(Bool, [PathErr(IOErr)])

    ## Returns `Bool.true` if the path exists on disk and is pointing at a directory.
    ##
    ## This function will traverse symbolic links to query information about the
    ## destination file. In case of broken symbolic links this will return `Bool.false`.
    is_dir! : Str => Try(Bool, [PathErr(IOErr)])

    ## Returns `Bool.true` if the path exists on disk and is pointing at a symbolic link.
    ##
    ## This function will not traverse symbolic links - it checks whether the path
    ## itself is a symlink.
    is_sym_link! : Str => Try(Bool, [PathErr(IOErr)])
}
