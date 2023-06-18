app "args"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Command,
        pf.Task,
    ]
    provides [main] to pf

main =

    # Run a command in a child process
    code <- Command.new "ls" |> Command.status |> Task.await

    codeStr = Num.toStr code

    Stdout.line "Child process returned with status \(codeStr)"
