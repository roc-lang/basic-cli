interface Command
    exposes [
        Command,
        new,
        status,
        output,
    ]
    imports [
        Task.{ Task },
        InternalTask,
        Effect,
    ]

Command := {
    program : Str,
    args : List Str,
    envs : Dict Str Str,
}

new : Str -> Command
new = \program ->
    {
        program,
        args: [],
        envs: Dict.empty {},
    }
    |> @Command

# TODO arg : Command, Str -> Command

# TODO args : Command, List Str -> Command

# TODO env : Command, {key: Str, value: Str} -> Command

# TODO envClear : Command -> Command

# TODO envs : Command, Dict Str Str -> Command

# TODO output : Command -> Task (List U8) I32
output : Command -> Task (List U8) U8
output = \@Command { program } ->
    Effect.commandOutput program
    |> InternalTask.fromEffect

## Execute command and return status code if the command returns non-zero code
status : Command -> Task U8 *
status = \@Command { program } ->
    Effect.commandStatus program
    |> Effect.map Ok
    |> InternalTask.fromEffect
