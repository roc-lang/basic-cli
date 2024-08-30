app [main] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main =
    Stdout.line! "What's your first name?"
    firstName = Stdin.line!
    Stdout.line! "What's your last name?"
    lastName = Stdin.line!

    Stdout.line "Hi, $(firstName) $(lastName)! 👋"
