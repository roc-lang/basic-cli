app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Path
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Demo of basic-cli Path functions

main! : List Arg => Result {} _
main! = |_args|

    path = Path.from_str("path.roc")

    a = Path.is_file!(path)?
    b = Path.is_dir!(path)?
    c = Path.is_sym_link!(path)?
    d = Path.type!(path)?

    Stdout.line!(
        """
        is_file: ${Inspect.to_str(a)}
        is_dir: ${Inspect.to_str(b)}
        is_sym_link: ${Inspect.to_str(c)}
        type: ${Inspect.to_str(d)}
        """
    )
