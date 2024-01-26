app "path-example"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main : Task {} I32
main =
    path = Path.fromStr "path.roc"
    a <- path |> Path.isFile |> Task.attempt
    b <- path |> Path.isDir |> Task.attempt
    c <- path |> Path.isSymLink |> Task.attempt
    d <- path |> Path.type |> Task.attempt

    Stdout.line "isFile: \(Inspect.toStr a) isDir: \(Inspect.toStr b) isSymLink: \(Inspect.toStr c) type: \(Inspect.toStr d)"

