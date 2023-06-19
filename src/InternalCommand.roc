interface InternalCommand
    exposes [
        Command,
        Output,
    ]
    imports []

Command : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
}

Output : {
    status : I32,
    stdout : List U8,
    stderr : List U8,
}