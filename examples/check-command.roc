## Check whether commands are available before trying to run them.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Cmd

report! : Str => Try({}, _)
report! = |name| {
	status = if Cmd.check_available!(name) "is available" else "is not available"
	Stdout.line!("${name} ${status}")
}

main! : List(OsStr) => Try({}, _)
main! = |_args| {

	# A command found on the PATH.
	report!("sh")?

	# A name that is not installed.
	report!("definitely-not-a-real-command-xyz")?

	Ok({})
}
