Env := [].{
    ## Reads the given environment variable.
    ##
    ## If the value is invalid Unicode, the invalid parts will be replaced with the
    ## [Unicode replacement character](https://unicode.org/glossary/#replacement_character).
    ##
    ## Returns an empty string if the variable is not found.
    var! : Str => Str

    ## Reads the [current working directory](https://en.wikipedia.org/wiki/Working_directory)
    ## from the environment.
    ##
    ## Returns an empty string if the cwd is unavailable.
    cwd! : {} => Str

    ## Gets the path to the currently-running executable.
    ##
    ## Returns an empty string if the path is unavailable.
    exe_path! : {} => Str
}
