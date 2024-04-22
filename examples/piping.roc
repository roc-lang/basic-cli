app "piping"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stdin,
        pf.Task.{ Task },
    ]
    provides [main] to pf

# Try piping in some text like this: `echo -e "test\n123" | roc piping.roc`
main : Task {} I32
main =
    lines = Task.loop! 0 count
    Stdout.line! "I read $(Num.toStr lines) lines from stdin."

count = \n ->
    when Stdin.line |> Task.result! is
        Ok _ -> Step (n + 1) |> Task.ok
        Err _ -> Done n |> Task.ok
