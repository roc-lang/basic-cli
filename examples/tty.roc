## Enable terminal raw mode, read one key, and restore normal behavior.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.Stdin
import pf.Tty

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Stdout.line!("Tty: enabling raw mode")?
	Tty.enable_raw_mode!()

	Stdout.line!("Press one key...")?
	input = Stdin.bytes!()

	Stdout.line!("Tty: disabling raw mode")?
	Tty.disable_raw_mode!()

	bytes = input?
	Stdout.line!("Read ${bytes.len().to_str()} byte(s).")?
	Ok({})
}
