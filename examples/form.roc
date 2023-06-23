app "form"
    packages { pf: "../src/main.roc" }
    imports [pf.Stdin, pf.Stdout, pf.Task.{ await, Task }]
    provides [main] to pf

main : Task {} I32
main =
    _ <- await (Stdout.line "What's your first name?")
    firstName <- await Stdin.line
    _ <- await (Stdout.line "What's your last name?")
    lastName <- await Stdin.line
    Stdout.line "Hi, \(firstName) \(lastName)! 👋"
