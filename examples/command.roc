app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

main! : {} => Result {} _
main! =
    statusExample! {}
    |> Result.mapErr StatusErr

    outputExample! {}
    |> Result.mapErr OutputErr

    execExample! {}
    |> Result.mapErr ExecErr

execExample! : {} => Result {} _
execExample! = \{} ->
    Cmd.exec! "echo" ["EXEC"]

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
statusExample! : {} => Result {} _
statusExample! = \{} ->
    Cmd.new "env"
    |> Cmd.arg "-v"
    |> Cmd.clearEnvs
    |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
    |> Cmd.status!
    |> Result.onErr \CmdError err ->
        when err is
            ExitCode code -> Stdout.line! "Child exited with non-zero code: $(Num.toStr code)"
            KilledBySignal -> Stdout.line! "Child was killed by signal"
            IOError str -> Stdout.line! "IOError executing: $(str)"

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
outputExample! : {} => Result {} _
outputExample! = \{} ->
    output =
        Cmd.new "env"
            |> Cmd.clearEnvs
            |> Cmd.env "FOO" "BAR"
            |> Cmd.args ["-v"]
            |> Cmd.output!
            |> Result.mapErr? \CmdOutputError err -> EnvFailed (Cmd.outputErrToStr err)

    output.stdout
    |> Str.fromUtf8
    |> Result.withDefault "Failed to decode stdout"
    |> Stdout.write!
