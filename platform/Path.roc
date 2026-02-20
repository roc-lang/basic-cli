import IOErr exposing [IOErr]

Path := [].{
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
