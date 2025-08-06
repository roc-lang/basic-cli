module [
    Cmd,
    new,
    arg,
    args,
    env,
    envs,
    clear_envs,
    exec_output!,
    exec!,
    exec_cmd!,
]

import InternalCmd
import InternalIOErr exposing [IOErr]
import Host

## Represents a command to be executed in a child process.
Cmd := InternalCmd.Command

## Simplest way to execute a command while inheriting stdin, stdout and stderr from parent.
## If you want to capture the output, use [exec_output!].
## ```
## # Call echo to print "hello world"
## Cmd.exec!("echo", ["hello world"]) ? |err| CmdEchoFailed(err)
## ```
exec! : Str, List Str => Result {} [ExecFailed Str (List Str) I32, FailedToGetExitCode IOErr]
exec! = |cmd_name, arguments|
    exit_code =
        new(cmd_name)
        |> args(arguments)
        |> exec_exit_code!?

    if exit_code == 0i32 then
        Ok({})
    else
        Err(ExecFailed(cmd_name, arguments, exit_code))

## Execute a Cmd while inheriting stdin, stdout and stderr from parent.
## You should prefer using `exec!`, only use this if you want to use [env], [envs] or [clear_envs].
## If you want to capture the output, use [exec_output!].
## ```
## # Execute `cargo build` with env var.
## Cmd.new("cargo")
## |> Cmd.arg("build")
## |> Cmd.env("RUST_BACKTRACE", "1")
## |> Cmd.exec_cmd!()?
## ```
exec_cmd! : Cmd => Result {} [ExecCmdFailed Cmd I32, FailedToGetExitCode IOErr]
exec_cmd! = |cmd|
    exit_code =
        exec_exit_code!(cmd)?

    if exit_code == 0i32 then
        Ok({})
    else
        Err(ExecCmdFailed(cmd, exit_code))

## Execute command and capture stdout, stderr and the exit code in [Output].
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
##
## TODO: explain when to use exec_output_bytes! vs exec_output!
exec_output! : Cmd =>
                    Result
                        {stdout_utf8 : Str, stderr_utf8_lossy : Str}
                        [
                            StdoutContainsInvalidUtf8([BadUtf8 { index : U64, problem : Str.Utf8Problem }]),
                            NonZeroExitCode({exit_code: I32, stdout_utf8_lossy: Str, stderr_utf8_lossy: Str}),
                            FailedToGetExitCode(IOErr)
                        ]
exec_output! = |@Cmd(cmd)|
    exec_res = Host.command_exec_output!(cmd)
    
    when exec_res is
        Ok({stdout_bytes, stderr_bytes}) ->
            stdout_utf8 = Str.from_utf8(stdout_bytes) ? |err| StdoutContainsInvalidUtf8(err)
            stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

            Ok({stdout_utf8, stderr_utf8_lossy})
        Err(inside_res) ->
            when inside_res is
                Ok({exit_code, stdout_bytes, stderr_bytes}) ->
                    stdout_utf8_lossy = Str.from_utf8_lossy(stdout_bytes)
                    stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

                    Err(NonZeroExitCode({exit_code, stdout_utf8_lossy, stderr_utf8_lossy}))
                Err(err) ->
                    Err(InternalIOErr.handle_err(err))
                    |> Result.map_err(FailedToGetExitCode)

# TODO exec_output_bytes

## Execute command and inherit stdin, stdout and stderr from parent. Returns the exit code.
## Helper function.
exec_exit_code! : Cmd => Result I32 [FailedToGetExitCode IOErr]
exec_exit_code! = |@Cmd(cmd)|
    Host.command_exec_exit_code!(cmd)
    |> Result.map_err(InternalIOErr.handle_err)
    |> Result.map_err(FailedToGetExitCode)

# This hits a compiler bug: Alias `6.IdentId(11)` not registered in delayed aliases! ...
# ## Converts output into a utf8 string. Invalid utf8 sequences in stderr are ignored.
# to_str : Output -> Result Str [BadUtf8 { index : U64, problem : Str.Utf8Problem }]
# to_str = |output|
#     InternalCmd.output_to_str(output)

# ## Converts output into a utf8 string, ignoring any invalid utf8 sequences.
# to_str_lossy : Output -> Str
# to_str_lossy = |output|
#     InternalCmd.output_to_str_lossy(output)

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
