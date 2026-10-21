## Read native and UTF-8 environment variables.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Env

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	editor = Env.var!("EDITOR")?

	Stdout.line!("Your favorite editor is ${editor.display()}!")?

	# A literal is UTF-8 text, and the operating system returns native units.
	# `OsStr` compares by content, so the two are equal when the text is.
	if editor == "vim" {
		Stdout.line!("Remember: `:q!` gets you out.")?
	} else {
		Stdout.line!("No need to remember how to quit vim.")?
	}

	letters = Env.var_str!("LETTERS")?

	joined_letters = Str.join_with(letters.split_on(","), " ")

	Stdout.line!("Your favorite letters are: ${joined_letters}")?

	# The same holds for `Dict` keys: a literal finds the native name.
	environment = Dict.from_list(Env.dict!())

	match environment.get("LETTERS") {
		Ok(value) => Stdout.line!("The environment dictionary agrees: ${value.display()}")?
		Err(KeyNotFound) => Stdout.line!("LETTERS is missing from the environment dictionary.")?
	}

	Ok({})
}
