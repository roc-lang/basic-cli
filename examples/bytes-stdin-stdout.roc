## Copy raw bytes from standard input to standard output and report the total.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Stdin
import pf.Stdout
import pf.Stderr

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	data = Stdin.read_to_end!()?

	Stdout.write_bytes!(data)?

	Stderr.line!("Copied ${data.len().to_str()} bytes from stdin to stdout.")?

	Ok({})
}
