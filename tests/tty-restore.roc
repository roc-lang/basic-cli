## Leave the terminal in raw mode in different ways, so that scripts/test.py can
## check the platform hands it back in the state it was found.
app [main!] { pf: platform "../platform/main.roc" }

import pf.IOErr
import pf.OsStr
import pf.Stdin
import pf.Stdout
import pf.Tty

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"repeat" => repeat!()
		"detached" => detached!()
		"error" => {
			enter_raw_mode!()?
			Err(LeftInRawMode)
		}
		"exit-code" => {
			enter_raw_mode!()?
			Err(Exit(3))
		}
		"crash" => {
			enter_raw_mode!()?
			crash "left in raw mode"
		}
		_ => Err(UnknownMode(mode))
	}
}

## The test harness sends a key once it has seen the terminal change mode.
enter_raw_mode! : () => Try({}, _)
enter_raw_mode! = || {
	Tty.enable_raw_mode!()?
	_key = Stdin.bytes!()?
	Ok({})
}

repeat! : () => Try({}, _)
repeat! = || {
	Tty.enable_raw_mode!()?
	Tty.enable_raw_mode!()?
	_key = Stdin.bytes!()?
	Tty.disable_raw_mode!()?
	Tty.disable_raw_mode!()?
	Stdout.line!("repeat: ok")?
	Ok({})
}

## Without a terminal there is no mode to change, and nothing to revert.
detached! : () => Try({}, _)
detached! = || {
	match Tty.enable_raw_mode!() {
		Ok({}) => Err(EnabledRawModeWithoutATerminal)
		Err(TtyErr(err)) => {
			Stdout.line!("enable failed: ${IOErr.to_str(err)}")?
			Tty.disable_raw_mode!()?
			Stdout.line!("disable without enable: ok")?
			Ok({})
		}
	}
}
