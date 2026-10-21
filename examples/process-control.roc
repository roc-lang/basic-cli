## Run a build command with live output and a five-minute deadline.
## Usage: roc process-control.roc -- cargo build --release
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Cmd
import pf.Duration
import pf.OsStr
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	(program, arguments) = match args {
		[command, .. as rest] => (command, rest)
		[] => return Err(MissingCommand)
	}

	# Pass native arguments directly: spaces and shell characters stay literal.
	child = Cmd.new(program)
		.args(arguments)
		.stdin(Null)
		.stdout(Tee)
		.stderr(Tee)
		.timeout(Duration.minutes(5))
		.manage_tree(True)
		.spawn!()?

	Stdout.line!("Running ${OsStr.display(program)} (pid ${child.pid().to_str()})")?

	# Both streams are drained concurrently. Tee also keeps a bounded capture.
	# The deadline terminates the managed process tree if the build gets stuck.
	output = match child.wait!() {
		Ok(finished) => finished
		Err(CmdErr(TimedOut(_))) => {
			Stderr.line!("Build timed out after five minutes")?
			return Err(Exit(124))
		}
		Err(other) => {
			return Err(other)
		}
	}

	match output.status {
		Exited(0) => Stdout.line!("Build completed successfully")
		status => {
			Stderr.line!("Build failed: ${Str.inspect(status)}")?
			Err(BuildFailed(status))
		}
	}
}
