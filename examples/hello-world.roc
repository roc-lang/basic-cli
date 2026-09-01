## Print a minimal greeting to standard output.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.1/HjwuwWAr7T9hqQXcb8VbxLJw1SzVhWQz5vvx4mnG3wDW.tar.zst" }

import pf.OsStr
import pf.Stdout

main! = |_args| {
	Stdout.line!("Hello, World!")?
	Ok({})
}
