## Measure a sleep interval and format the current UTC time.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Utc
import pf.Sleep

main! : List(OsStr) => Try({}, _)
main! = |_args| {

	start : U128
	start = Utc.now!()

	Stdout.line!("Started at ${Utc.to_iso_8601(start)}")?

	Sleep.seconds!(1)

	finish : U128
	finish = Utc.now!()

	duration_ms = Utc.delta_as_millis(finish, start)
	duration_nanos = Utc.delta_as_nanos(finish, start)

	Stdout.line!("Completed in ${duration_ms.to_str()} ms (${duration_nanos.to_str()} ns)")?

	Ok({})
}
