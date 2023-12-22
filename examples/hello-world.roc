app "hello-world"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main : Task {} I32
main =
    Stdout.line "Hello, World!" 
