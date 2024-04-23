app "path-example"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Path,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main = run |> Task.onErr \err -> crash "ERROR: $(Inspect.toStr err)"

run =
    path = Path.fromStr "path.roc"
    a = Path.isFile! path
    b = Path.isDir! path
    c = Path.isSymLink! path
    d = Path.type! path

    Stdout.line "isFile: \(Inspect.toStr a) isDir: \(Inspect.toStr b) isSymLink: \(Inspect.toStr c) type: \(Inspect.toStr d)"

