app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path

main! = \{} ->

    path = Path.fromStr "path.roc"

    a = try Path.isFile! path
    b = try Path.isDir! path
    c = try Path.isSymLink! path
    d = try Path.type! path

    Stdout.line! "isFile: $(Inspect.toStr a) isDir: $(Inspect.toStr b) isSymLink: $(Inspect.toStr c) type: $(Inspect.toStr d)"
