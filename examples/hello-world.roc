## Print a minimal greeting to standard output.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0/GNN5tt2gKdX4dhawg4915C4YB193woHFdcCkz31fhGxv.tar.zst" }

import pf.OsStr
import pf.Stdout

main! = |_args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
