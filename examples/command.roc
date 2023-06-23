app "command"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Command,
        pf.Process,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =
    {} <- first |> Task.await
    {} <- second |> Task.await

    Process.exit 0

# Run "env" with verbose option, clear all environment variables, and pass in
# "FOO" and "BAZ".
first : Task {} I32
first =

    result <-
        Command.new "env"
        |> Command.arg "-v"
        |> Command.clearEnvs
        |> Command.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Command.status
        |> Task.attempt

    when result is
        Ok {} -> Stdout.line "Success"
        Err (ExitCode code) ->
            codeStr = Num.toStr code
            Stdout.line "Child exited with non-zero code: \(codeStr)"

        Err KilledBySignal -> Stdout.line "Child was killed by signal"
        Err (IOError err) -> Stdout.line "IOError executing: \(err)"

# Run "stat" with environment variable "FOO" set to "BAR" and three arguments: "--format", "'%A'", and "LICENSE".
# Capture stdout and stderr and print them.
second : Task {} I32
second =
    output <-
        Command.new "stat"
        |> Command.env "FOO" "BAR"
        |> Command.args [
            "--format",
            "'%A'", # print permission bits in human readable form
            "LICENSE" # filename
        ]
        |> Command.output
        |> Task.await

    status =
        when output.status is
            Ok {} -> "Success"
            Err (ExitCode code) ->
                codeStr = Num.toStr code
                "Child exited with non-zero code: \(codeStr)"

            Err KilledBySignal -> "Child was killed by signal"
            Err (IOError err) -> "IOError executing: \(err)"

    stdout = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"
    stderr = Str.fromUtf8 output.stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STATUS \(status)\nSTDOUT \(stdout)\nSTDERR \(stderr)\n"
