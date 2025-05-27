app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Reading piped text from stdin, for example: `echo "hey" | roc ./examples/stdin-pipe.roc`

main! : List Arg => Result {} _
main! = |_args|

    # Data is only sent with Stdin.line! if the user presses Enter,
    # so you'll need to use read_to_end! to read data that was piped in without a newline.
    piped_in = Stdin.read_to_end!({})?
    piped_in_str = Str.from_utf8(piped_in)?

    Stdout.line!("This is what you piped in: \"${piped_in_str}\"")
