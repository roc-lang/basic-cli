## Check whether commands are available before trying to run them.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0/4rAQg8kUYZ3Vksr4qMQHpaFYNiHSn9GgS7gVxghd1XYV.tar.zst" }

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
