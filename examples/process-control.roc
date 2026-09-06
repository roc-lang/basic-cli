## Run a build command with live output and a five-minute deadline.
## Usage: roc process-control.roc -- cargo build --release
app [main!] { pf: platform "../platform/main.roc" }

import pf.Cmd
import pf.OsStr
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	(program, arguments) = match args.drop_first(1) {
		[command, .. as rest] => (command, rest)
		[] => return Err(MissingCommand)
	}

	# Pass native arguments directly: spaces and shell characters stay literal.
	child = Cmd.new(program)
		.args(arguments)
		.stdin(Null)
		.stdout(Tee)
		.stderr(Tee)
		.timeout_ms(300_000)
		.manage_tree(Bool.True)
		.spawn!() ? |err| StartFailed(err)

	pid = child.pid!() ? |err| ProcessFailed(err)
	Stdout.line!("Running ${OsStr.display(program)} (pid ${pid.to_str()})")?

	# Both streams are drained concurrently. Tee also keeps a bounded capture.
	# The deadline terminates the managed process tree if the build gets stuck.
	output = child.wait!() ? |err| BuildInterrupted(err)
	match output.status {
		Exited(0) => Stdout.line!("Build completed successfully")
		status => {
			Stderr.line!("Build failed: ${Str.inspect(status)}")?
			Err(BuildFailed(status))
		}
	}
}
