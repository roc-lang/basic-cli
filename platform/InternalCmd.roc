module [
    Command,
    OutputFromHostSuccess,
    OutputFromHostFailure,
    to_str,
]

Command : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # TODO change this to list of tuples? [key0, value0, key1, value1, key2, value2, ...]
    clear_envs : Bool,
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostSuccess : {
    stderr_bytes : List U8,
    stdout_bytes : List U8,
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostFailure : {
    stderr_bytes : List U8,
    stdout_bytes : List U8,
    exit_code : I32,
}

to_str : Command -> Str
to_str = |cmd|
    envs_str =
        cmd.envs
        #|> List.map(|(key, value)| "${key}=${value}")
        |> Str.join_with(" ")
        |> Str.trim()
        |> (|trimmed_str| if Str.is_empty(trimmed_str) then "" else "envs: ${trimmed_str}")

    clear_envs_str = if cmd.clear_envs then ", clear_envs: true" else ""
    
    """
    { cmd: ${cmd.program}, args: ${Str.join_with(cmd.args, " ")}${envs_str}${clear_envs_str} }
    """