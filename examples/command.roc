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
    
    code <- 
        Command.new "ls" 
        |> Command.status 
        |> Task.await

    if code == 0 then
        Stdout.line "Success, returned 0 status code"
    else
        codeStr = Num.toStr code
        Stdout.line "Failed with \(codeStr) status code"

# Run a command in a child process, return output
second : Task {} U32
second = 
    output <- 
        Command.new "ls" 
        |> Command.output 
        |> Task.mapFail \_ -> 1 
        |> Task.await

    status = Num.toStr output.status
    stdout = Str.fromUtf8 output.stdout |> Result.withDefault "Failed to decode stdout"
    stderr = Str.fromUtf8 output.stderr |> Result.withDefault "Failed to decode stderr"

    Stdout.write "STATUS \(status)\nSTDOUT\n \(stdout)STDERR \(stderr)\n"
