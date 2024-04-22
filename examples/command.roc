app "command"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Cmd,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main : Task {} I32
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
            ExitCode code ->
                Stdout.line "Command `env` (statusExample) exited with non-zero code: $(Num.toStr code)."
            KilledBySignal ->
                Stdout.line "Command `env` (statusExample) was killed by signal."
            IOError errStr ->
                Stdout.line "Command `env` (statusExample) hit IOError: $(errStr)."
        
# Similar to above but with `Cmd.output` we now get back the record `Output` containing the `stdout` and `stderr` of
# the command.
outputExample =
    output =
        Cmd.new "env"
        |> Cmd.clearEnvs
        |> Cmd.env "FOO" "BAR"
        |> Cmd.args ["-v"]
        |> Cmd.output
        |> Task.onErr! \(output, err) ->
            when err is
                ExitCode code ->
                    stderr = 
                        output.stderr |> Str.fromUtf8 |> Result.withDefault ""

                    Task.err (EnvCmdError "Command `env` (outputExample) exited with non-zero code: $(Num.toStr code), stderr:\n\t$(stderr)")
                KilledBySignal ->
                    Task.err (EnvCmdError "Command `env` (outputExample) was killed by signal.")
                IOError ioErr ->
                    Task.err (EnvCmdError "Command `env` (outputExample) hit IOError executing: $(ioErr).")

    output.stdout 
    |> Str.fromUtf8 
    |> Result.withDefault "Failed to decode stdout with Utf-8."
    |> Stdout.write