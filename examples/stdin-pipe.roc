## Read piped bytes to end-of-input and validate them as UTF-8.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Stdin
import pf.Stdout

# Reading piped text from stdin, for example: `echo "hey" | roc ./examples/stdin-pipe.roc`

main! : List(OsStr) => Try({}, _)
main! = |_| {
	# Data is only sent with Stdin.line! if the user presses Enter,
	# so you'll need to use read_to_end! to read data that was piped in without a newline.
	piped_in = Stdin.read_to_end!()?
	piped_in_str = Str.from_utf8(piped_in)?

	Stdout.line!("This is what you piped in: \"${piped_in_str}\"")?

	Ok({})
}
