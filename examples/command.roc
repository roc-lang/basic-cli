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
    {} <- first |> Task.await
    {} <- second |> Task.await

    Task.ok {}

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
first : Task {} I32
first =

    result <-
        Cmd.new "env"
        |> Cmd.arg "-v"
        |> Cmd.clearEnvs
        |> Cmd.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Cmd.status
        |> Task.attempt

    when result is
        Ok {} -> Stdout.line "Success"
        Err (ExitCode code) ->
            codeStr = Num.toStr code
            Stdout.line "Child exited with non-zero code: $(codeStr)"

        Err KilledBySignal -> Stdout.line "Child was killed by signal"
        Err (IOError err) -> Stdout.line "IOError executing: $(err)"

# Run "stat" with environment variable "FOO" set to "BAR" and three arguments: "--format", "'%A'", and "LICENSE".
# Capture stdout and stderr and print them.
second : Task {} I32
second =
    (status, stdout, stderr) <-
        Cmd.new "stat"
        |> Cmd.env "FOO" "BAR"
        |> Cmd.args [
            "--format",
            "'%A'", # print permission bits in human readable form
            "LICENSE", # filename
        ]
        |> Cmd.output
        |> Task.map \output -> ("Success", output.stdout, output.stderr)
        |> Task.onErr \(output, err) ->
            when err is
                ExitCode code -> Task.ok ("Child exited with non-zero code: $(Num.toStr code)", output.stdout, output.stderr)
                KilledBySignal -> Task.ok ("Child was killed by signal", output.stdout, output.stderr)
                IOError ioErr -> Task.ok ("IOError executing: $(ioErr)", output.stdout, output.stderr)
        |> Task.await

    stdoutStr = Str.fromUtf8 stdout |> Result.withDefault "Failed to decode stdout"
    stderrStr = Str.fromUtf8 stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STATUS $(status)\nSTDOUT $(stdoutStr)\nSTDERR $(stderrStr)\n"
