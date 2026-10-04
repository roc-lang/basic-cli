## Read piped bytes to end-of-input and validate them as UTF-8.
app [main!] { pf: platform "../platform/main.roc" }

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
