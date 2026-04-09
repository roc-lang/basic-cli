import IOErr exposing [IOErr]

File := [].{
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
