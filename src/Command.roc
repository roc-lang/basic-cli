interface Command
    exposes [
        Command,
        Output,
        new,
        status,
        output,
    ]
    imports [
        Task.{ Task },
        InternalTask,
        InternalCommand,
        Effect,
    ]

Command := InternalCommand.Command

Output : InternalCommand.Output

new : Str -> Command
new = \program ->
    @Command {
        program,
        args: [],
        envs: [],
    }

# TODO arg : Command, Str -> Command

# TODO args : Command, List Str -> Command

# TODO env : Command, {key: Str, value: Str} -> Command

# TODO envClear : Command -> Command

# TODO envs : Command, Dict Str Str -> Command

output : Command -> Task Output U8
output = \@Command cmd ->
    Effect.commandOutput (Box.box cmd)
    |> InternalTask.fromEffect

## Execute command and return status code if the command returns non-zero code
## panic if the command fails to execute
status : Command -> Task U8 *
status = \@Command cmd ->
    Effect.commandStatus (Box.box cmd)
    |> Effect.map Ok
    |> InternalTask.fromEffect
