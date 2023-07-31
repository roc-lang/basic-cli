interface Cmd
    exposes [
        Cmd,
        Output,
        Error,
        new,
        arg,
        args,
        env,
        envs,
        clearEnvs,
        status,
        output,
    ]
    imports [
        Task.{ Task },
        InternalTask,
        InternalCommand,
        Effect,
    ]

## Represents a command to be executed in a child process.
Cmd := InternalCommand.Command

## Errors from executing a command.
Error : InternalCommand.CommandErr

## Represents the output of a command.
Output : {
    stdout : List U8,
    stderr : List U8,
}

## Create a new command to execute the given program in a child process.
new : Str -> Cmd
new = \program ->
    @Cmd {
        program,
        args: [],
        envs: [],
        clearEnvs: Bool.false,
    }

## Add a single argument to the command.
##
## ```
## # Represent the command "ls -l"
## Cmd.new "ls"
## |> Cmd.arg "-l"
## ```
##
arg : Cmd, Str -> Cmd
arg = \@Cmd cmd, value ->
    @Cmd
        { cmd &
            args: List.append cmd.args value,
        }

## Add multiple arguments to the command.
##
## ```
## # Represent the command "ls -l -a"
## Cmd.new "ls"
## |> Cmd.args ["-l", "-a"]
## ```
##
args : Cmd, List Str -> Cmd
args = \@Cmd cmd, values ->
    @Cmd
        { cmd &
            args: List.concat cmd.args values,
        }

## Add a single environment variable to the command.
##
## ```
## # Run "env" and add the environment variable "FOO" with value "BAR"
## Cmd.new "env"
## |> Cmd.env "FOO" "BAR"
## ```
##
env : Cmd, Str, Str -> Cmd
env = \@Cmd cmd, key, value ->
    @Cmd
        { cmd &
            envs: List.concat cmd.envs [key, value],
        }

## Add multiple environment variables to the command.
##
## ```
## # Run "env" and add the variables "FOO" and "BAZ"
## Cmd.new "env"
## |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
## ```
##
envs : Cmd, List (Str, Str) -> Cmd
envs = \@Cmd cmd, keyValues ->
    values = keyValues |> List.joinMap \(key, value) -> [key, value]
    @Cmd
        { cmd &
            envs: List.concat cmd.envs values,
        }

## Clear all environment variables, and prevent inheriting from parent, only
## the environment variables provided to command are available to the child.
##
## ```
## # Represents "env" with only "FOO" environment variable set
## Cmd.new "env"
## |> Cmd.clearEnvs
## |> Cmd.env "FOO" "BAR"
## ```
##
clearEnvs : Cmd -> Cmd
clearEnvs = \@Cmd cmd ->
    @Cmd { cmd & clearEnvs: Bool.true }

## Execute command and capture stdout and stderr
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
##
output : Cmd -> Task Output (Output, Error)
output = \@Cmd cmd ->
    Effect.commandOutput (Box.box cmd)
    |> Effect.map \internalOutput ->
        out = 
            {
                stdout: internalOutput.stdout,
                stderr: internalOutput.stderr,
            }

        when internalOutput.status is
            Ok {} -> Ok (out)
            Err err -> Err (out, err)
        
    |> InternalTask.fromEffect

## Execute command and inheriting stdin, stdout and stderr from parent
##
status : Cmd -> Task {} Error
status = \@Cmd cmd ->
    Effect.commandStatus (Box.box cmd)
    |> InternalTask.fromEffect
