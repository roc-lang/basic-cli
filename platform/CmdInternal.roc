import IOErr exposing [IOErr]

CmdInternal :: {
    args : List(Str),
    clear_envs : Bool,
    envs : List(Str),
    program : Str, 
}.{
    command_exec_exit_code! : CmdInternal => Try(I32, IOErr)

    #command_exec_output! : CmdInternal => Try(OutputFromHostSuccess, (Try(OutputFromHostFailure, IOErr)))
}