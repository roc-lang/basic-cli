app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stdin
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Counts the number of lines piped in. Example run: `echo -e "test\n123" | roc piping.roc`

main! : List Arg => Result {} _
main! = |_args|
    lines = count!(0)
    Stdout.line!("I read ${Num.to_str(lines)} lines from stdin.")

count! = |n|
    when Stdin.line!({}) is
        Ok(_) -> count!((n + 1))
        Err(_) -> n
