app "command"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Cmd,
        pf.Task.{ Task },
    ]
    provides [main] to pf

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
    |> Task.onErr \err -> 
        when err is
            ExitCode code -> Stdout.line "Child exited with non-zero code: $(Num.toStr code)"
            KilledBySignal -> Stdout.line "Child was killed by signal"
            IOError str -> Stdout.line "IOError executing: $(str)"
        
# Run "env" with verbose option, clear all environment variables, and pass in
# only as an environment variable "FOO"
outputExample =
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