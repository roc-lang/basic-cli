module [
    Command,
    Output,
    CommandErr,
    handleCommandErr,
]

CommandErr : [
    ExitCode I32,
    KilledBySignal,
    IOError Str,
]

handleCommandErr : List U8 -> CommandErr
handleCommandErr = \err ->
    when err is
        ['E', 'C', .. as rest] ->
            code = rest |> Str.fromUtf8 |> Result.try Str.toI32 |> Result.withDefault -99
            ExitCode code

        ['K', 'S'] -> KilledBySignal
        other ->
            msg = Str.fromUtf8 other |> Result.withDefault "BadUtf8 from host"

            IOError msg

Command : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
    clearEnvs : Bool,
}

Output : {
    status : Result {} (List U8),
    stdout : List U8,
    stderr : List U8,
}
