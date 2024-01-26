app "piping"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stdin,
        pf.Task.{ Task },
    ]
    provides [main] to pf

# Try piping in some text like this: `echo -e "test\n123" | roc piping.roc`
main =
    lines <- Task.loop 0 count |> Task.await
    Stdout.line "I read $(Num.toStr lines) lines from stdin."

count = \n ->
    result <- Stdin.line |> Task.await
    state =
        when result is
            Input _ -> Step (n + 1)
            End -> Done n
    Task.ok state
