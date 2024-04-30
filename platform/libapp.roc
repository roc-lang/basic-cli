app "stub"
    packages { pf: "main.roc" }
    imports [pf.Task.{ Task }]
    provides [main] to pf

main = Task.ok {}
