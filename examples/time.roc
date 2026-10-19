## Measure a sleep interval and format the current UTC time.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Duration
import pf.Monotonic
import pf.OsStr
import pf.Sleep
import pf.Stdout
import pf.Utc

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Utc is a point in calendar time, for showing to people.
	Stdout.line!("Started at ${Utc.now!().to_iso_8601()}")?

	# Monotonic measures elapsed time, unaffected by changes to the wall clock.
	start = Monotonic.now!()

	Sleep.seconds!(1)?

	Stdout.line!("Completed in ${start.elapsed!().to_str()}")?

	# A computed wait is a method on the Duration: sleep for whatever is left
	# of the interval, which is nothing if it has already passed.
	interval = Duration.millis(1200)
	interval.minus(start.elapsed!()).sleep!()?

	if start.elapsed!() >= interval {
		Stdout.line!("Waited out the ${interval.to_str()} interval")?
	} else {
		Stdout.line!("Woke before the ${interval.to_str()} interval was over")?
	}

	Ok({})
}
