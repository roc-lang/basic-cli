app "echo"
    packages { pf: "../src/main.roc" }
    imports [pf.Stdin, pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main : Str -> Task Str I32
main = \arg ->
    _ <- Task.await (Stdout.line "🗣  Shout into this cave and hear the \(arg)! 👂👂👂")

    Stdin.line
