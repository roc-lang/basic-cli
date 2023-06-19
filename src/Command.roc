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
Error : InternalCommand.CommandErr
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

## Execute command and capture stdout and stderr
##
## Stdin is not inherited from the parent and any attempt by the child process 
## to read from the stdin stream will result in the stream immediately closing.
##
output : Command -> Task Output Error
output = \@Command cmd ->
    Effect.commandOutput (Box.box cmd)
    |> InternalTask.fromEffect

## Execute command and inheriting stdin, stdout and stderr from parent
##
status : Command -> Task {} Error
status = \@Command cmd ->
    Effect.commandStatus (Box.box cmd)
    |> InternalTask.fromEffect
