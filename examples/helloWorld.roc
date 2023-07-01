app "helloWorld"
    packages { pf: "../src/main.roc" }
    imports [pf.Stdout]
    provides [main] to pf

main : Task {} I32
main =
    Stdout.line "Hello, World!"