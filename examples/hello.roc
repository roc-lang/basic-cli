app [main!] { pf: platform "../platform/main.roc" }

import pf.Host
import pf.Stdout

main! : Host => Try({}, [Exit(I32)])
main! = |host| {
	Stdout.line!("Hello from basic-cli!")
	args = host.args!()
	Stdout.line!("${Str.inspect(args)}")
	Ok({})
}
