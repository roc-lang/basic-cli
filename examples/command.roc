app "args"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Command,
        pf.Task,
    ]
    provides [main] to pf

main =

    # Run a command and return the status code
    maybeStatus <-
        Command.new "ls"
        |> Command.status
        |> Task.attempt

    when maybeStatus is
        Ok {} -> Stdout.line "Success"
        Err code ->
            codeStr = Num.toStr code
            Stdout.line "Command failed with status code \(codeStr)"
