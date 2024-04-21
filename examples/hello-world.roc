app "hello-world"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main : Task {} _
main =
    Stdout.line! "Hello, World!"

    Task.ok {}