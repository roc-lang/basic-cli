import Cmd exposing [Cmd]
import IOErr exposing [IOErr]

CmdInternal :: [].{
    command_exec_exit_code! : Cmd => Try(I32, IOErr)

    command_exec_output! : Cmd => Try(OutputFromHostSuccess, (Try(OutputFromHostFailure, IOErr)))
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostSuccess : {
    stderr_bytes : List(U8),
    stdout_bytes : List(U8),
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostFailure : {
    stderr_bytes : List(U8),
    stdout_bytes : List(U8),
    exit_code : I32,
}