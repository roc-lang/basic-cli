app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdin
import pf.Stdout

main! = \_args ->

    Stdout.line!("What's your first name?")?

    first = Stdin.line!({})?

    Stdout.line!("What's your last name?")?

    last = Stdin.line!({})?

    Stdout.line!("Hi, $(first) $(last)! 👋")
