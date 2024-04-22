app "command"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Cmd,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =
    runEnv!
    runStat!

    Cmd.exec! "echo" ["EXEC"]

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
runEnv =
    result =
        Cmd.new "env"
            |> Cmd.arg "-v"
            |> Cmd.clearEnvs
            |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
            |> Cmd.status
            |> Task.result!

    when result is
        Ok {} -> Stdout.line "STATUS"
        Err (ExitCode code) ->
            codeStr = Num.toStr code
            Stdout.line "Child exited with non-zero code: $(codeStr)"

        Err KilledBySignal -> Stdout.line "Child was killed by signal"
        Err (IOError err) -> Stdout.line "IOError executing: $(err)"

# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
runStat =
    output =
        Cmd.new "env"
            |> Cmd.clearEnvs
            |> Cmd.env "FOO" "BAR"
            |> Cmd.args ["-v"]
            |> Cmd.output
            |> Task.onErr! \(output, err) ->
                when err is
                    ExitCode code -> Task.err (StatError "Child exited with non-zero code: $(Num.toStr code), stderr: $(output.stderr |> Str.fromUtf8 |> Result.withDefault "")")
                    KilledBySignal -> Task.err (StatError "Child was killed by signal")
                    IOError ioErr -> Task.err (StatError "IOError executing: $(ioErr)")

    output.stdout 
    |> Str.fromUtf8 
    |> Result.withDefault "Failed to decode stdout"
    |> Stdout.write
