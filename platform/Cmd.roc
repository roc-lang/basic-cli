module [
    Cmd,
    Output,
    Err,
    outputErrToStr,
    new,
    arg,
    args,
    env,
    envs,
    clearEnvs,
    status!,
    output!,
    exec!,
]

import InternalCommand
import Host

## Represents a command to be executed in a child process.
Cmd := InternalCommand.Command implements [Inspect]

## Errors from executing a command.
Err : InternalCommand.CommandErr

outputErrToStr : (Output, Err) -> Str
outputErrToStr = \(_, err) ->
    when err is
        ExitCode code -> "Child exited with non-zero code: $(Num.toStr code)"
        KilledBySignal -> "Child was killed by signal"
        IOError ioErr -> "IOError executing: $(ioErr)"

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
## ! Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
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
## ! Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
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
output! : Cmd => Result Output [CmdOutputError (Output, Err)]
output! = \@Cmd cmd ->
    internalOutput = Host.commandOutput! (Box.box cmd)

    out = {
        stdout: internalOutput.stdout,
        stderr: internalOutput.stderr,
    }

    when internalOutput.status is
        Ok {} -> Ok out
        Err bytes -> Err (CmdOutputError (out, InternalCommand.handleCommandErr bytes))

## Execute command and inherit stdin, stdout and stderr from parent
##
status! : Cmd => Result {} [CmdError Err]
status! = \@Cmd cmd ->
    Host.commandStatus! (Box.box cmd)
    |> Result.mapErr \bytes -> CmdError (InternalCommand.handleCommandErr bytes)

## Execute command and inherit stdin, stdout and stderr from parent
##
## ```
## # Call echo to print "hello world"
## Cmd.exec! "echo" ["hello world"]
## ```
exec! : Str, List Str => Result {} [CmdError Err]
exec! = \program, arguments ->
    new program
    |> args arguments
    |> status!
