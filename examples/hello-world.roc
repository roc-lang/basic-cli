app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! = \_args ->
    Stdout.line! "Hello, World!"
