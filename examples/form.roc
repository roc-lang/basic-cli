app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = \_args ->

    try Stdout.line! "What's your first name?"

    first = try Stdin.line! {}

    try Stdout.line! "What's your last name?"

    last = try Stdin.line! {}

    Stdout.line! "Hi, $(first) $(last)! 👋"
