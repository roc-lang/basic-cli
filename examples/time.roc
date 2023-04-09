app "time"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Task,
        pf.Time,
    ]
    provides [main] to pf

main =
    millis <- Time.now |> Task.await

    millisStr = Num.toStr millis
    
    Stdout.line "Milliseconds since UNIX_EPOCH: \(millisStr)"
