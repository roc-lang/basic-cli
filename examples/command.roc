app "args"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Command,
        pf.Process,
        pf.Task.{Task},
    ]
    provides [main] to pf

main =
    {} <- first |> Task.await
    {} <- second |> Task.await

    Process.exit 0

    # second
    
# Run a command in a child process, return status code
first : Task {} U32
first = 
    
    {} <- 
        Command.new "env" 
        |> Command.arg "-v"
        |> Command.env "FOO" "BAR"
        |> Command.status
        |> Task.onFail \_ -> crash "first failed"
        |> Task.await

    Stdout.line "Successfully executed"

# Run a command in a child process, return output
second : Task {} U32
second = 
    output <- 
        Command.new "ls"
        |> Command.args ["-l", "-a"]
        |> Command.envs [("FOO", "BAR"), ("BAZ", "DUCK")]
        |> Command.output 
        |> Task.onFail \_ -> crash "second failed"
        |> Task.await

    stdout = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"
    stderr = Str.fromUtf8 output.stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STDOUT\n \(stdout)STDERR \(stderr)\n"
