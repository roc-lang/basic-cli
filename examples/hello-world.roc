app "hello-world"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main =
    Stdout.write! "Hello,"
    Stdout.line! " World!"
