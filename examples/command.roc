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
        Err (KilledBySignal) -> Stdout.line "Child was killed by signal"
        Err (IOError err) -> Stdout.line "IOError executing: \(err)"

# Run "ls" with environment variable "FOO" and two arguments, "-l" and "-a".
# Capture stdout and stderr and print them.
second : Task {} U32
second =
    output <-
        Command.new "ls"
        |> Command.env "FOO" "BAR"
        |> Command.args ["-l", "-a"]
        |> Command.output
        |> Task.await

    stdout = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"
    stderr = Str.fromUtf8 output.stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STDOUT\n \(stdout)STDERR \(stderr)\n"
