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
        Ok {} -> Stdout.line "Success"
        Err (ExitCode code) ->
            codeStr = Num.toStr code
            Stdout.line "Child exited with non-zero code: $(codeStr)"

        Err KilledBySignal -> Stdout.line "Child was killed by signal"
        Err (IOError err) -> Stdout.line "IOError executing: $(err)"

# Run "stat" with environment variable "FOO" set to "BAR" and three arguments:
# "--format", "'%A'", and "LICENSE". Capture stdout and stderr and print them.
runStat =
    output =
        Cmd.new "stat"
            |> Cmd.env "FOO" "BAR"
            |> Cmd.args [
                "--format",
                "'%A'", # print permission bits in human readable form
                "LICENSE", # filename
            ]
            |> Cmd.output
            |> Task.onErr! \(output, err) ->
                when err is
                    ExitCode code -> Task.err (StatError "Child exited with non-zero code: $(Num.toStr code), stderr: $(output.stderr |> Str.fromUtf8 |> Result.withDefault "")")
                    KilledBySignal -> Task.err (StatError "Child was killed by signal")
                    IOError ioErr -> Task.err (StatError "IOError executing: $(ioErr)")

    stdoutStr = output.stdout |> Str.fromUtf8 |> Result.withDefault "Failed to decode stdout"
    stderrStr = output.stderr |> Str.fromUtf8 |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STATUS SUCCESS \nSTDOUT $(stdoutStr)\nSTDERR $(stderrStr)\n"
