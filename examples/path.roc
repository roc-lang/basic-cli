app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path

main! = \{} ->

    path = Path.from_str "path.roc"

    a = Path.is_file!? path
    b = Path.is_dir!? path
    c = Path.is_sym_link!? path
    d = Path.type!? path

    Stdout.line! "isFile: $(Inspect.toStr a) isDir: $(Inspect.toStr b) isSymLink: $(Inspect.toStr c) type: $(Inspect.toStr d)"
