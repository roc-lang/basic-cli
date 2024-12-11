app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = \{} ->

    try Stdout.line! "What's your first name?"

    firstName = try Stdin.line! {}

    try Stdout.line! "What's your last name?"

    lastName = try Stdin.line! {}

    Stdout.line! "Hi, $(firstName) $(lastName)! 👋"
