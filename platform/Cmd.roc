module [
    Cmd,
    new,
    arg,
    args,
    env,
    envs,
    clear_envs,
    exec_output!,
    exec_output_bytes!,
    exec!,
    exec_cmd!,
    exec_exit_code!,
]

import InternalCmd exposing [to_str]
import InternalIOErr exposing [IOErr]
import Host

## Simplest way to execute a command while inheriting stdin, stdout and stderr from parent.
## If you want to capture the output, use [exec_output!] instead.
## ```
## # Call echo to print "hello world"
## Cmd.exec!("echo", ["hello world"])?
## ```
exec! : Str, List Str => Result {} [ExecFailed { command : Str, exit_code : I32 }, FailedToGetExitCode { command : Str, err : IOErr }]
exec! = |cmd_name, arguments|
    exit_code =
        new(cmd_name)
        |> args(arguments)
        |> exec_exit_code!()?

    if exit_code == 0i32 then
        Ok({})
    else
        command = "${cmd_name} ${Str.join_with(arguments, " ")}"
        Err(ExecFailed({ command, exit_code }))

## Execute a Cmd while inheriting stdin, stdout and stderr from parent.
## You should prefer using [exec!] instead, only use this if you want to use [env], [envs] or [clear_envs].
## If you want to capture the output, use [exec_output!] instead.
## ```
## # Execute `cargo build` with env var.
## Cmd.new("cargo")
## |> Cmd.arg("build")
## |> Cmd.env("RUST_BACKTRACE", "1")
## |> Cmd.exec_cmd!()?
## ```
exec_cmd! : Cmd => Result {} [ExecCmdFailed { command : Str, exit_code : I32 }, FailedToGetExitCode { command : Str, err : IOErr }]
exec_cmd! = |@Cmd(cmd)|
    exit_code =
        exec_exit_code!(@Cmd(cmd))?

    if exit_code == 0i32 then
        Ok({})
    else
        Err(ExecCmdFailed({ command: to_str(cmd), exit_code }))

## Execute command and capture stdout and stderr.
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
##
## Use [exec_output_bytes!] instead if you want to capture the output in the original form as bytes.
## [exec_output_bytes!] may also be used for maximum performance, because you may be able to avoid unnecessary UTF-8 conversions.
##
## ```
## cmd_output =
##     Cmd.new("echo")
##     |> Cmd.args(["Hi"])
##     |> Cmd.exec_output!()?
##
## Stdout.line!("Echo output: ${cmd_output.stdout_utf8}")?
## ```
##
exec_output! :
    Cmd
    =>
    Result
        { stdout_utf8 : Str, stderr_utf8_lossy : Str }
        [
            StdoutContainsInvalidUtf8 { cmd_str : Str, err : [BadUtf8 { index : U64, problem : Str.Utf8Problem }] },
            NonZeroExitCode { command : Str, exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str },
            FailedToGetExitCode { command : Str, err : IOErr },
        ]
exec_output! = |@Cmd(cmd)|
    exec_res = Host.command_exec_output!(cmd)

    when exec_res is
        Ok({ stderr_bytes, stdout_bytes }) ->
            stdout_utf8 = Str.from_utf8(stdout_bytes) ? |err| StdoutContainsInvalidUtf8({ cmd_str: to_str(cmd), err })
            stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

            Ok({ stdout_utf8, stderr_utf8_lossy })

        Err(inside_res) ->
            when inside_res is
                Ok({ exit_code, stderr_bytes, stdout_bytes }) ->
                    stdout_utf8_lossy = Str.from_utf8_lossy(stdout_bytes)
                    stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

                    Err(NonZeroExitCode({ command: to_str(cmd), exit_code, stdout_utf8_lossy, stderr_utf8_lossy }))

                Err(err) ->
                    Err(FailedToGetExitCode({ command: to_str(cmd), err: InternalIOErr.handle_err(err) }))

## Execute command and capture stdout and stderr in the original form as bytes.
##
## > Stdin is not inherited from the parent and any attempt by the child process
## > to read from the stdin stream will result in the stream immediately closing.
##
## Use [exec_output!] instead if you want to get the output as UTF-8 strings.
##
## ```
## cmd_output_bytes =
##     Cmd.new("echo")
##     |> Cmd.args(["Hi"])
##     |> Cmd.exec_output_bytes!()?
##
## Stdout.line!("${Inspect.to_str(cmd_output_bytes)}")? # {stderr_bytes: [], stdout_bytes: [72, 105, 10]}
## ```
##
exec_output_bytes! : Cmd => Result { stderr_bytes : List U8, stdout_bytes : List U8 } [FailedToGetExitCodeB InternalIOErr.IOErr, NonZeroExitCodeB { exit_code : I32, stderr_bytes : List U8, stdout_bytes : List U8 }]
exec_output_bytes! = |@Cmd(cmd)|
    exec_res = Host.command_exec_output!(cmd)

    when exec_res is
        Ok({ stderr_bytes, stdout_bytes }) ->
            Ok({ stdout_bytes, stderr_bytes })

        Err(inside_res) ->
            when inside_res is
                Ok({ exit_code, stderr_bytes, stdout_bytes }) ->
                    Err(NonZeroExitCodeB({ exit_code, stdout_bytes, stderr_bytes }))

                Err(err) ->
                    Err(FailedToGetExitCodeB(InternalIOErr.handle_err(err)))

## Execute command and inherit stdin, stdout and stderr from parent. Returns the exit code.
##
## You should prefer using [exec!] or [exec_cmd!] instead, only use this if you want to take a specific action based on a **specific non-zero exit code**.
## For example, `roc check` returns exit code 1 if there are errors, and exit code 2 if there are only warnings.
## So, you could use `exec_exit_code!` to ignore warnings on `roc check`.
##
## ```
## exit_code =
##        Cmd.new("cat")
##        |> Cmd.args(["non_existent.txt"])
##        |> Cmd.exec_exit_code!()?
##
## Stdout.line!("${Num.to_str(exit_code)}")? # "1"
## ```
##
exec_exit_code! : Cmd => Result I32 [FailedToGetExitCode { command : Str, err : IOErr }]
exec_exit_code! = |@Cmd(cmd)|
    Host.command_exec_exit_code!(cmd)
    |> Result.map_err(InternalIOErr.handle_err)
    |> Result.map_err(|err| FailedToGetExitCode({ command: to_str(cmd), err }))

## Represents a command to be executed in a child process.
Cmd := InternalCmd.Command

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
## the environment variables provided by [env] or [envs] are available to the child.
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
## ❗ Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
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
## ❗ Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
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
