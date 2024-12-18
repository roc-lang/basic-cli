app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

main! = \{} ->
    try status_example! {}

    try output_example! {}

    try exec_example! {}

    Ok {}

exec_example! : {} => Result {} _
exec_example! = \{} -> Cmd.exec! "echo" ["EXEC"]

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
status_example! : {} => Result {} _
status_example! = \{} ->
    result =
        Cmd.new "env"
        |> Cmd.arg "-v"
        |> Cmd.clear_envs
        |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Cmd.status!

    when result is
        Ok exit_code if exit_code == 0 -> Ok {}
        Ok exit_code -> Stdout.line! "Child exited with non-zero code: $(Num.toStr exit_code)"
        Err err -> Stdout.line! "Error executing command: $(Inspect.toStr err)"

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
output_example! : {} => Result {} _
output_example! = \{} ->

    output =
        Cmd.new "env"
        |> Cmd.clear_envs
        |> Cmd.env "FOO" "BAR"
        |> Cmd.args ["-v"]
        |> Cmd.output!

    msg = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"

    Stdout.write! msg
