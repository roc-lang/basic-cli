app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

main! = \_args ->
    try statusExample! {}

    try outputExample! {}

    try execExample! {}

    Ok {}

execExample! = \{} -> Cmd.exec! "echo" ["EXEC"]

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
statusExample! = \{} ->
    result =
        Cmd.new "env"
        |> Cmd.arg "-v"
        |> Cmd.clearEnvs
        |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Cmd.status!

    when result is
        Ok {} -> Ok {}
        Err (CmdError (ExitCode code)) -> Stdout.line! "Child exited with non-zero code: $(Num.toStr code)"
        Err (CmdError KilledBySignal) -> Stdout.line! "Child was killed by signal"
        Err (CmdError (IOError str)) -> Stdout.line! "IOError executing: $(str)"

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
outputExample! = \{} ->

    output =
        Cmd.new "env"
        |> Cmd.clearEnvs
        |> Cmd.env "FOO" "BAR"
        |> Cmd.args ["-v"]
        |> Cmd.output!
        |> try

    msg = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"

    Stdout.write! msg
