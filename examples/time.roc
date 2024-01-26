app "time"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task,
        pf.Utc,
        pf.Sleep,
    ]
    provides [main] to pf

main =
    start <- Utc.now |> Task.await

    {} <- Sleep.millis 1500 |> Task.await

    finish <- Utc.now |> Task.await

    duration = Utc.deltaAsNanos start finish |> Num.toStr

    Stdout.line "Completed in $(duration)ns"
