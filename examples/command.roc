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
first : Task {} []
first = 
    
    code <- Command.new "ls" |> Command.status |> Task.await

    if code == 0 then
        Stdout.line "Success, returned 0 status code"
    else
        codeStr = Num.toStr code
        Stdout.line "Failed with \(codeStr) status code"

# Run a command in a child process, return output
second : Task {} []
second = 
    result <- 
        Command.new "ls" 
        |> Command.output 
        |> Task.attempt

    when result is 
        Ok bytes -> 
            bytesStr = Str.fromUtf8 bytes |> Result.withDefault "Failed to decode output"
            Stdout.line "Succes, output is: \(bytesStr)"
        Err code ->
            codeStr = Num.toStr code
            Stdout.line "Failed with \(codeStr) status code"
