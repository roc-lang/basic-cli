## Read native and UTF-8 environment variables.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.Env

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	editor = Env.var!("EDITOR")?

	Stdout.line!("Your favorite editor is ${editor.display()}!")?

	letters = Env.var_str!("LETTERS")?

	joined_letters = Str.join_with(letters.split_on(","), " ")

	Stdout.line!("Your favorite letters are: ${joined_letters}")?

	Ok({})
}
