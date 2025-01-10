app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout

main! = \_args ->
    Stdout.line!("Hello, World!")
