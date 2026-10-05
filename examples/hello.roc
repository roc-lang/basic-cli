## Greet a name supplied as a native command-line argument.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	name : Str
	name = greeting_name(args)

	Stdout.line!("Hello, ${name}, from basic-cli!")?

	Ok({})
}

greeting_name : List(OsStr) -> Str
greeting_name = |args|
	match args {
		[first, ..] => OsStr.display(first)
		[] => "friend"
	}
