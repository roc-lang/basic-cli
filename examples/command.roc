## Run commands, capture their output, and set their env vars.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Cmd

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Run a command on your terminal. Anything but exit code 0 is an error.
	Cmd.new("echo").arg("Hello").call!()?

	# Capture what a command prints, as text. A string that interpolates is
	# passed as it is: no shell splits it or expands it.
	name = "Roc"
	greeting = Cmd.new("echo").arg("Hi ${name}").capture!()?
	Stdout.line!("Captured: ${greeting.trim()}")?

	# Run a command with a controlled environment. Inspecting a command shows
	# the names of its variables, never their values.
	env_cmd = Cmd.new("/usr/bin/env")
		.clear_envs()
		.envs([("FOO", "BAR"), ("BAZ", "DUCK")])
	Stdout.line!("Command config: ${Str.inspect(env_cmd)}")?
	env_cmd.call!()?

	# `run!` returns the exit status and the output as data, so a command that
	# fails is yours to handle. Output is printed as text.
	output = Cmd.new("cat").arg("non_existent.txt").run!()?
	Stdout.line!("Status: ${Str.inspect(output.status)}")?
	Stdout.line!("Stderr: ${output.stderr_utf8_lossy().trim()}")?

	# The same, with the command printing to your terminal.
	status = Cmd.new("cat").arg("non_existent.txt").inherit_stdio().run!()?.status
	Stdout.line!("Status again: ${Str.inspect(status)}")?

	# Requiring success turns that status into an error that carries the output.
	match Cmd.new("cat").arg("non_existent.txt").run!()?.require_success() {
		Ok(_) => Stdout.line!("cat succeeded")?
		Err(BadExitStatus(failed)) => Stdout.line!("Failed: ${failed.command}")?
	}

	# The output in its original form, as bytes.
	bytes = Cmd.new("echo").arg("Hi").run!()?.require_success()?.stdout_bytes
	Stdout.line!("Bytes: ${Str.inspect(bytes)}")?

	# A program that does not exist is an error you can match on.
	match Cmd.new("definitely-not-a-real-command-xyz").call!() {
		Err(CmdErr(StartFailed(NotFound, program))) => Stdout.line!("Not installed: ${OsStr.display(program)}")?
		Err(CmdErr(err)) => Stdout.line!("Could not run: ${err.to_str()}")?
		Err(BadExitStatus(failed)) => Stdout.line!("Failed: ${failed.command}")?
		Err(Interrupted) => {
			return Err(Interrupted)
		}
		Ok({}) => {}
	}

	Ok({})
}
