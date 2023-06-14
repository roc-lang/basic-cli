app "time"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Task,
        pf.Utc,
    ]
    provides [main] to pf

main =
    start <- Utc.now |> Task.await

    {} <- Utc.sleepMillis 1500 |> Task.await

    finish <- Utc.now |> Task.await

    duration = Utc.deltaAsNanos start finish |> Num.toStr

    Stdout.line "Completed in \(duration)ns"
