app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

main =
    statusExample |> Task.mapErr! StatusErr
    outputExample |> Task.mapErr! OutputErr
    execExample |> Task.mapErr! ExecErr

execExample = Cmd.exec "echo" ["EXEC"]

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
statusExample =
    Cmd.new "env"
    |> Cmd.arg "-v"
    |> Cmd.clearEnvs
    |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
    |> Cmd.status
    |> Task.onErr \CmdError err ->
        when err is
            ExitCode code -> Stdout.line "Child exited with non-zero code: $(Num.toStr code)"
            KilledBySignal -> Stdout.line "Child was killed by signal"
            IOError str -> Stdout.line "IOError executing: $(str)"

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
outputExample : Task {} _
outputExample =
    output =
        Cmd.new "env"
            |> Cmd.clearEnvs
            |> Cmd.env "FOO" "BAR"
            |> Cmd.args ["-v"]
            |> Cmd.output
            |> Task.mapErr! \CmdOutputError err -> EnvFailed (Cmd.outputErrToStr err)

    output.stdout
    |> Str.fromUtf8
    |> Result.withDefault "Failed to decode stdout"
    |> Stdout.write
