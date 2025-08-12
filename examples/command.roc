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

    # To execute and capture the output (stdout, stderr, and exit code) without inheriting your terminal.
    cmd_output =
        Cmd.new("echo")
        |> Cmd.args(["Hi"])
        |> Cmd.exec_output!()?

    Stdout.line!(
        """
        stdout:${cmd_output.stdout_utf8}
        stderr:${cmd_output.stderr_utf8_lossy}
        """
    )?

    # To run a command with environment variables.
    cmd_output_env =
        Cmd.new("env")
        |> Cmd.clear_envs # You probably don't need to clear all other environment variables, this is just an example.
        |> Cmd.env("FOO", "BAR")
        |> Cmd.envs([("BAZ", "DUCK"), ("XYZ", "ABC")]) # Set multiple environment variables at once with `envs`
        |> Cmd.args(["-v"])
        |> Cmd.exec_output!()?

    Stdout.line!(
        """
        stdout:${cmd_output_env.stdout_utf8}
        stderr:${cmd_output_env.stderr_utf8_lossy}
        """
    )?

    # To execute and just get the exit code (prints to your terminal).
    exit_code =
        Cmd.new("echo")
        |> Cmd.args(["Yo"])
        |> Cmd.exec_exit_code!()?

    Stdout.line!("Exit code: ${Num.to_str(exit_code)}")?

    Ok({})
