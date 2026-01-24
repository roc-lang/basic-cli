Dir := [].{
    ## **NotFound** - An entity was not found, often a file.
    ##
    ## **PermissionDenied** - The operation lacked the necessary privileges to complete.
    ##
    ## **AlreadyExists** - An entity already exists, often a file.
    ##
    ## **NotADirectory** - The path was not a directory when a directory was expected.
    ##
    ## **NotEmpty** - The directory is not empty.
    ##
    ## **Other** - A custom error that does not fall under any other I/O error kind.
    IOErr := [
        NotFound,
        PermissionDenied,
        AlreadyExists,
        NotADirectory,
        NotEmpty,
        Other(Str),
    ]

    ## Creates a new, empty directory at the provided path.
    ##
    ## If the parent directories do not exist, they will not be created.
    ## Use [Dir.create_all!] to create parent directories as needed.
    create! : Str => Try({}, [DirErr(IOErr)])

    ## Creates a new, empty directory at the provided path, including any parent directories.
    ##
    ## If the directory already exists, this will succeed without error.
    create_all! : Str => Try({}, [DirErr(IOErr)])

    ## Deletes an empty directory.
    ##
    ## Fails if the directory is not empty. Use [Dir.delete_all!] to delete
    ## a directory and all its contents.
    delete_empty! : Str => Try({}, [DirErr(IOErr)])

    ## Deletes a directory and all of its contents recursively.
    ##
    ## Use with caution!
    delete_all! : Str => Try({}, [DirErr(IOErr)])

    ## Lists the contents of a directory.
    ##
    ## Returns the paths of all files and directories within the specified directory.
    list! : Str => Try(List(Str), [DirErr(IOErr)])
}
