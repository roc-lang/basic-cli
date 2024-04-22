app "countdown"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdin, pf.Stdout, pf.Task.{ await, loop }]
    provides [main] to pf

main : Task {} I32
main =
    Stdout.line! "\nLet's count down from 3 together - all you have to do is press <ENTER>."
    _ = Stdin.line!

    loop 3 tick

tick = \n ->
    if n == 0 then
        Stdout.line! "🎉 SURPRISE! Happy Birthday! 🎂"

        Task.ok (Done {})
    else
        Stdout.line! (n |> Num.toStr |> \s -> "$(s)...")
        _ = Stdin.line!

        Task.ok (Step (n - 1))
