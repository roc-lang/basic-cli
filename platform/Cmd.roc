module [
    Cmd,
    Output,
    new,
    arg,
    args,
    env,
    envs,
    clear_envs,
    status!,
    output!,
    exec!,
]

import InternalCmd
import InternalIOErr
import Host

## Represents a command to be executed in a child process.
Cmd := InternalCmd.Command

## Represents the output of a command.
##
## Output is a record:
## ```
## {
##    status : Result I32 InternalIOErr.IOErr,
##    stdout : List U8,
##    stderr : List U8,
## }
## ```
##
Output : InternalCmd.Output

## Create a new command to execute the given program in a child process.
new : Str -> Cmd
new = |program|
    @Cmd(
        {
            program,
            args: [],
            envs: [],
            clear_envs: Bool.false,
        },
    )

## Add a single argument to the command.
## ! Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
##
## ```
## # Represent the command "ls -l"
## Cmd.new("ls")
## |> Cmd.arg("-l")
## ```
##
arg : Cmd, Str -> Cmd
arg = |@Cmd(cmd), value|
    @Cmd({ cmd & args: List.append(cmd.args, value) })

## Add multiple arguments to the command.
## ! Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
##
## ```
## # Represent the command "ls -l -a"
## Cmd.new("ls")
## |> Cmd.args(["-l", "-a"])
## ```
##
args : Cmd, List Str -> Cmd
args = |@Cmd(cmd), values|
    @Cmd({ cmd & args: List.concat(cmd.args, values) })

## Add a single environment variable to the command.
##
## ```
## # Run "env" and add the environment variable "FOO" with value "BAR"
## Cmd.new("env")
## |> Cmd.env("FOO", "BAR")
## ```
##
env : Cmd, Str, Str -> Cmd
env = |@Cmd(cmd), key, value|
    @Cmd({ cmd & envs: List.concat(cmd.envs, [key, value]) })

## Add multiple environment variables to the command.
##
## ```
## # Run "env" and add the variables "FOO" and "BAZ"
## Cmd.new("env")
## |> Cmd.envs([("FOO", "BAR"), ("BAZ", "DUCK")])
## ```
##
envs : Cmd, List (Str, Str) -> Cmd
envs = |@Cmd(cmd), key_values|
    values = key_values |> List.join_map(|(key, value)| [key, value])
    @Cmd({ cmd & envs: List.concat(cmd.envs, values) })

## Clear all environment variables, and prevent inheriting from parent, only
## the environment variables provided to command are available to the child.
##
## ```
## # Represents "env" with only "FOO" environment variable set
## Cmd.new("env")
## |> Cmd.clear_envs
## |> Cmd.env("FOO", "BAR")
## ```
##
clear_envs : Cmd -> Cmd
clear_envs = |@Cmd(cmd)|
    @Cmd({ cmd & clear_envs: Bool.true })

## Execute command and capture stdout, stderr and the exit code in [Output].
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
##
output! : Cmd => Output
output! = |@Cmd(cmd)|
    Host.command_output!(cmd)
    |> InternalCmd.from_host_output

## Execute command and inherit stdin, stdout and stderr from parent
##
status! : Cmd => Result I32 [CmdStatusErr InternalIOErr.IOErr]
status! = |@Cmd(cmd)|
    Host.command_status!(cmd)
    |> Result.map_err(InternalIOErr.handle_err)
    |> Result.map_err(CmdStatusErr)

## Execute command and inherit stdin, stdout and stderr from parent
##
## ```
## # Call echo to print "hello world"
## Cmd.exec!("echo", ["hello world"]) ? |err| CmdEchoFailed(err)
## ```
exec! : Str, List Str => Result {} [CmdStatusErr InternalIOErr.IOErr]
exec! = |program, arguments|
    exit_code =
        new(program)
        |> args(arguments)
        |> status!?

    if exit_code == 0i32 then
        Ok({})
    else
        Err(CmdStatusErr(Other("Non-zero exit code ${Num.to_str(exit_code)}")))
