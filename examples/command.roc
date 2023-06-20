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
first : Task {} U32
first =

    {} <-
        Command.new "env"
        |> Command.arg "-v"
        |> Command.clearEnvs
        |> Command.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Command.status
        |> Task.onFail \_ -> crash "first failed"
        |> Task.await

    Stdout.line "Success"

# Run "ls" with environment variable "FOO" and two arguments, "-l" and "-a".
# Capture stdout and stderr and print them.
second : Task {} U32
second =
    output <-
        Command.new "ls"
        |> Command.env "FOO" "BAR"
        |> Command.args ["-l", "-a"]
        |> Command.output
        |> Task.onFail \_ -> crash "second failed"
        |> Task.await

    stdout = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"
    stderr = Str.fromUtf8 output.stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STDOUT\n \(stdout)STDERR \(stderr)\n"
