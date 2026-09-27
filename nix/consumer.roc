app [main!] { pf: platform "@platformUrl@" }

import pf.Stdout

main! = |_args| {
	Stdout.line!("Hello from basic-cli!")?
	Ok({})
}
