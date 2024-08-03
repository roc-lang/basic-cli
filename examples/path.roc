app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path

main = run |> Task.onErr \err -> crash "ERROR: $(Inspect.toStr err)"

run =
    path = Path.fromStr "path.roc"
    a = Path.isFile! path
    b = Path.isDir! path
    c = Path.isSymLink! path
    d = Path.type! path

    Stdout.line "isFile: $(Inspect.toStr a) isDir: $(Inspect.toStr b) isSymLink: $(Inspect.toStr c) type: $(Inspect.toStr d)"

