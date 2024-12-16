app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = \{} ->

    Stdout.line!? "What's your first name?"

    first = Stdin.line!? {}

    Stdout.line!? "What's your last name?"

    last = Stdin.line!? {}

    Stdout.line! "Hi, $(first) $(last)! 👋"
