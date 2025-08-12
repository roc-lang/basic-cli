module [
    Command,
    OutputFromHostSuccess,
    OutputFromHostFailure,
    to_str,
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

to_str : Command -> Str
to_str = |cmd|
    envs_str =
        cmd.envs
        #|> List.map(|(key, value)| "${key}=${value}")
        |> Str.join_with(" ")

    clear_envs_str = if cmd.clear_envs then "true" else "false"
    
    """
    cmd: ${cmd.program}
    args: ${Str.join_with(cmd.args, " ")}
    envs: ${envs_str}
    clear_envs: ${clear_envs_str}
    """