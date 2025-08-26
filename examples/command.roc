app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd
import pf.Arg exposing [Arg]

# Different ways to run commands like you do in a terminal. 

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|

    # Simplest way to execute a command (prints to your terminal).
    Cmd.exec!("echo", ["Hello"])?

    # To execute and capture the output (stdout and stderr) without inheriting your terminal.
    cmd_output =
        Cmd.new("echo")
        |> Cmd.args(["Hi"])
        |> Cmd.exec_output!()?

    Stdout.line!("${Inspect.to_str(cmd_output)}")?

    # To run a command with environment variables.
    Cmd.new("env")
    |> Cmd.clear_envs # You probably don't need to clear all other environment variables, this is just an example.
    |> Cmd.env("FOO", "BAR")
    |> Cmd.envs([("BAZ", "DUCK"), ("XYZ", "ABC")]) # Set multiple environment variables at once with `envs`
    |> Cmd.args(["-v"])
    |> Cmd.exec_cmd!()?

    # To execute and just get the exit code (prints to your terminal).
    # Prefer using `exec!` or `exec_cmd!`.
    exit_code =
        Cmd.new("cat")
        |> Cmd.args(["non_existent.txt"])
        |> Cmd.exec_exit_code!()?

    Stdout.line!("Exit code: ${Num.to_str(exit_code)}")?

    # To execute and capture the output (stdout and stderr) in the original form as bytes without inheriting your terminal.
    # Prefer using `exec_output!`.
    cmd_output_bytes =
        Cmd.new("echo")
        |> Cmd.args(["Hi"])
        |> Cmd.exec_output_bytes!()?

    Stdout.line!("${Inspect.to_str(cmd_output_bytes)}")?

    Ok({})
