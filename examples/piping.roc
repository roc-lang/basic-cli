app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stdin

# Try piping in some text like this: `echo -e "test\n123" | roc piping.roc`
main! = \{} ->
    lines = count! 0
    Stdout.line! "I read $(Num.toStr lines) lines from stdin."

count! = \n ->
    when Stdin.line! {} is
        Ok _ -> count! (n + 1)
        Err _ -> n
