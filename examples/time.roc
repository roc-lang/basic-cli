## Measure a sleep interval and format the current UTC time.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

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
