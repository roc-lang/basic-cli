app "form"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdin, pf.Stdout, pf.Task.{ await, Task }]
    provides [main] to pf

main =
    Stdout.line! "What's your first name?"
    firstName = Stdin.line!

    Stdout.line! "What's your last name?"
    lastName = Stdin.line!

    Stdout.line "Hi, $(firstName) $(lastName)! 👋"
