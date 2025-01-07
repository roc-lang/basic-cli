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

    Stdout.line! "isFile: $(Inspect.to_str a) isDir: $(Inspect.to_str b) isSymLink: $(Inspect.to_str c) type: $(Inspect.to_str d)"
