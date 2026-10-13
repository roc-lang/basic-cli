## Append lines to a log file without replacing its existing contents.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

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
