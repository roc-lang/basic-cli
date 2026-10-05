## Print a minimal greeting to standard output.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout

main! = |_args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
