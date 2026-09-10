## Greet a name supplied as a native command-line argument.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0-rc1/3hT3SoHZ6qbEsa9qVFLUW3547U5LeoNd1KbpqLpz4r1i.tar.zst" }

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
