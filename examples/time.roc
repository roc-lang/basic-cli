app "time"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Task,
        pf.Utc,
        pf.File,
        pf.Path,
    ]
    provides [main] to pf

main =
    start <- Utc.now |> Task.await

    {} <- slowTask |> Task.await

    finish <- Utc.now |> Task.await

    duration = Utc.deltaAsNanos start finish |> Num.toStr

    Stdout.line "Completed in \(duration)ns"

slowTask : Task.Task {} []
slowTask =

    path = Path.fromStr "not-a-file-but-try-to-read-anyway"

    result <- File.readUtf8 path |> Task.attempt

    when result is
        _ -> Stdout.line "Tried to open a file..."
