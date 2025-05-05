app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Reading text from stdin

main! : List Arg => Result {} _
main! = |_args|

    Stdout.line!("What's your first name?")?

    first = Stdin.line!({})?

    Stdout.line!("What's your last name?")?

    last = Stdin.line!({})?

    Stdout.line!("Hi, ${first} ${last}! 👋")
