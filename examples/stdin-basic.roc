## Prompt for two lines of standard input and print a greeting.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Stdin
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Stdout.line!("What's your first name?")?
	first = read_name!() ? |_| MissingFirstName

	Stdout.line!("What's your last name?")?
	last = read_name!() ? |_| MissingLastName

	Stdout.line!("Hi, ${first} ${last}! \u(1F44B)")?
	Ok({})
}

## An empty line is a real answer, so it is `Ok("")`; input that has ended is
## `Err(EndOfInput)`. Here both mean there is no name.
read_name! : () => Try(Str, [NoName, Interrupted, BadUtf8({ problem : Str.Utf8Problem, index : U64 }), StdinErr(_)])
read_name! = ||
	match Stdin.line!() {
		Ok("") => Err(NoName)
		Ok(name) => Ok(name)
		Err(EndOfInput) => Err(NoName)
		Err(BadUtf8(problem)) => Err(BadUtf8(problem))
		Err(Interrupted) => Err(Interrupted)
		Err(StdinErr(err)) => Err(StdinErr(err))
	}
