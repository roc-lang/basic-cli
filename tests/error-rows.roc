## Use platform functions as function values beside another error, so that
## their error rows have to widen. Error rows are closed at the host boundary
## by design; this file stops checking if a public platform wrapper forwards a
## hosted result without rebuilding its error into an open row.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.OsStr
import pf.Random
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	# A second error beside the platform's, so each `?` below must widen.
	if args.len() > 0 {
		return Err(UnexpectedArguments)
	}

	stdout!()?
	stderr!()?
	random!()?
	env!()?

	Stdout.line!("error rows: ok")
}

stdout! : () => Try({}, _)
stdout! = || {
	line! = Stdout.line!
	write! = Stdout.write!
	write_bytes! = Stdout.write_bytes!

	line!("stdout line")?
	write!("stdout write")?
	write_bytes!("\n".to_utf8())?

	Ok({})
}

stderr! : () => Try({}, _)
stderr! = || {
	line! = Stderr.line!
	write! = Stderr.write!
	write_bytes! = Stderr.write_bytes!

	line!("stderr line")?
	write!("stderr write")?
	write_bytes!("\n".to_utf8())?

	Ok({})
}

random! : () => Try({}, _)
random! = || {
	seed_u64! = Random.seed_u64!
	seed_u32! = Random.seed_u32!

	_seed_u64 = seed_u64!()?
	_seed_u32 = seed_u32!()?

	Stdout.line!("random seeds: ok")
}

env! : () => Try({}, _)
env! = || {
	cwd! = Env.cwd!
	exe_path! = Env.exe_path!
	program_name! = Env.program_name!
	var_str! = Env.var_str!

	_cwd = cwd!()?
	_exe_path = exe_path!()?
	_program_name = program_name!()?
	greeting = var_str!("ERROR_ROWS_GREETING")?

	Stdout.line!("env: ${greeting}")
}
