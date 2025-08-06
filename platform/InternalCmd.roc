module [
    Command,
    OutputFromHostSuccess,
    OutputFromHostFailure,
]

Command : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
    clear_envs : Bool,
}

OutputFromHostSuccess : {
    stdout_bytes : List U8,
    stderr_bytes : List U8,
}

OutputFromHostFailure : {
    exit_code : I32,
    stdout_bytes : List U8,
    stderr_bytes : List U8,
}