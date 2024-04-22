app "time"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task,
        pf.Utc,
        pf.Sleep,
    ]
    provides [main] to pf

main : Task {} I32
main =
    start = Utc.now!

    Sleep.millis! 1500

    finish = Utc.now!

    duration = Num.toStr (Utc.deltaAsNanos start finish)

    Stdout.line! "Completed in $(duration)ns"
