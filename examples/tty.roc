## Enable terminal raw mode, read one key, and restore normal behavior.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Stdin
import pf.Tty

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Stdout.line!("Tty: enabling raw mode")?
	Tty.enable_raw_mode!()?

	# Raw mode turns off the terminal's own line handling, so end lines with "\r\n".
	Stdout.write!("Press one key...\r\n")?

	# If this fails, the platform restores the terminal when the app exits.
	bytes = Stdin.bytes!()?

	Tty.disable_raw_mode!()?
	Stdout.line!("Tty: disabled raw mode")?

	Stdout.line!("Read ${bytes.len().to_str()} byte(s).")?
	Ok({})
}
