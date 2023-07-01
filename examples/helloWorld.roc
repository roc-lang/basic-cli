app "helloWorld"
    packages { pf: "../src/main.roc" }
    imports [pf.Stdout]
    provides [main] to pf

main =
    Stdout.line "Hello, World!"