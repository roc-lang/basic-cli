app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd
import pf.Arg exposing [Arg]

# Different ways to run commands like you do in a terminal. 

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|

    # Simplest way to execute a command
    exec_example!({})?

    # To execute and capture the output (includes stderr)
    output_example!({})?

    # To execute and get the exit code
    status_example!({})?

    Ok({})

exec_example! : {} => Result {} _
exec_example! = |{}| Cmd.exec!("echo", ["EXEC"])

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
status_example! : {} => Result {} _
status_example! = |{}|
    result =
        Cmd.new("env")
        |> Cmd.arg("-v")
        |> Cmd.clear_envs
        |> Cmd.envs([("FOO", "BAR"), ("BAZ", "DUCK")])
        |> Cmd.status!

    when result is
        Ok(exit_code) if exit_code == 0 -> Ok({})
        Ok(exit_code) -> Stdout.line!("Child exited with non-zero code: ${Num.to_str(exit_code)}")
        Err(err) -> Stdout.line!("Error executing command: ${Inspect.to_str(err)}")

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
output_example! : {} => Result {} _
output_example! = |{}|

    output =
        Cmd.new("env")
        |> Cmd.clear_envs
        |> Cmd.env("FOO", "BAR")
        |> Cmd.args(["-v"])
        |> Cmd.output!

    msg = Str.from_utf8(output.stdout) |> Result.with_default("Failed to decode stdout")

    Stdout.write!(msg)
