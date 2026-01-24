app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path

# Demo of basic-cli Path functions

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    path = "path.roc"

    a = Path.is_file!(path)
    b = Path.is_dir!(path)
    c = Path.is_sym_link!(path)

    Stdout.line!(
        \\is_file: ${Str.inspect(a)}
        \\is_dir: ${Str.inspect(b)}
        \\is_sym_link: ${Str.inspect(c)}
    )

    Ok({})
}
