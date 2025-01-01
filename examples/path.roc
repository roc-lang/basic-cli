app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path

# To run this example: check the README.md in this folder

main! = \_args ->

    path = Path.from_str "path.roc"

    a = try Path.is_file! path
    b = try Path.is_dir! path
    c = try Path.is_sym_link! path
    d = try Path.type! path

    Stdout.line! "isFile: $(Inspect.toStr a) isDir: $(Inspect.toStr b) isSymLink: $(Inspect.toStr c) type: $(Inspect.toStr d)"
