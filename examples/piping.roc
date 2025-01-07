app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stdin

# To run this example: check the README.md in this folder

# Try piping in some text like this: `echo -e "test\n123" | roc piping.roc`
main! = \_args ->
    lines = count! 0
    Stdout.line! "I read $(Num.to_str lines) lines from stdin."

count! = \n ->
    when Stdin.line! {} is
        Ok _ -> count! (n + 1)
        Err _ -> n
