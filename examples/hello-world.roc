app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|
    Stdout.line!("Hello, World!")
