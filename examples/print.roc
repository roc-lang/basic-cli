## Write text, lines and lists to standard output and standard error.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Stderr

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Print a string to stdout with a newline
	Stdout.line!("Hello, world!")?

	# Print without a newline
	Stdout.write!("No newline after me.")?

	# Print a string to stderr with a newline
	Stderr.line!("Hello, error!")?

	# Print a string to stderr without a newline
	Stderr.write!("Err with no newline after.")?

	# Print a list to stdout
	lst = ["Foo", "Bar", "Baz"]
	for str in lst {
		Stdout.line!(str)?
	}

	# Use inspect to convert a value into a nice string representation for debugging
	Stdout.line!(Str.inspect(lst))?

	Ok({})
}
