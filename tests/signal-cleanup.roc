## Model an acquired external resource with a file and clean it up after a stop.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Duration
import pf.OsStr
import pf.Path
import pf.Signal
import pf.Stdin
import pf.Stdout
import pf.System
import pf.Tty

main! : List(OsStr) => Try({}, _)
main! = |args| {
	match System.target!().os() {
		Linux(os) => Signal.catch!([Interrupt, Terminate(os.unix())])?
		MacOS(os) => Signal.catch!([Interrupt, Terminate(os.unix())])?
		Windows(_) => Signal.catch!([Interrupt])?
	}
	Signal.catch!([])?
	Signal.catch!([Interrupt])?
	Stdout.line!("ready for stop")?
	Path.write_utf8!("resource-state.txt", "acquired")?
	if !args.map(OsStr.display).contains("service") {
		Tty.enable_raw_mode!()?
	}
	result = if args.map(OsStr.display).contains("stdin") {
		match Stdin.line!() {
			Ok(_) => Ok({})
			Err(err) => Err(err)
		}
	} else {
		Duration.seconds(60).sleep!()
	}
	match result {
		Err(Interrupted) => {
			events = Signal.poll!()
			if events.is_empty() {
				return Err(MissingSignal)
			}
			Tty.disable_raw_mode!()?
			Path.write_utf8!("resource-state.txt", "cleaned")?
			if Path.read_utf8!("resource-state.txt")? != "cleaned" {
				return Err(CleanupFailed)
			}
			Stdout.line!("cleanup complete: ${Str.inspect(events)}")?
			if !Signal.poll!().is_empty() {
				return Err(SignalNotAcknowledged)
			}
			Ok({})
		}
		Err(other) => Err(other)
		Ok({}) => Err(ExpectedInterruption)
	}
}
