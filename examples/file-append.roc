## Append lines to a log file without replacing its existing contents.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	log : Path
	log = "events.log"

	# The first append creates the file; later ones add to the end.
	log.append_utf8!("started\n")?
	log.append_utf8!("working\n")?
	log.append_bytes!(Str.to_utf8("finished\n"))?

	contents = log.read_utf8!()?

	# Cleanup
	log.delete!()?

	Stdout.write!("The log contains:\n${contents}")?

	Ok({})
}
