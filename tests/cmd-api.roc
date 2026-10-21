## Run this executable as its own child process and print what `Cmd` returns,
## so that scripts/test.py can check each way of running a command, the errors,
## and the `Child` methods on every operating system without other programs.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Cmd
import pf.Duration
import pf.Env
import pf.System
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdin
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	match args.map(OsStr.display) {
		["--helper", .. as rest] => as_helper!(rest)
		[] => {
			running!()?
			errors!()?
			streams!()?
			file_outputs!()?
			child!()?
			deadlines!()?
			compact!()?
			function_values!()?
			Stdout.line!("cmd: ok")
		}
		# An error nothing handles is printed by the platform.
		["unhandled-timeout"] => {
			_output = helper!(["hang"]).timeout(Duration.seconds(2)).run!()?
			Ok({})
		}
		["unhandled-start-failure"] => missing().env("API_TOKEN", "hunter2").call!()
		["unhandled-bad-exit"] => {
			_text = helper!(["exit", "3"]).env("API_TOKEN", "hunter2").stderr(Capture).capture!()?
			Ok({})
		}
		other => Err(UnknownMode(other))
	}
}

## What this executable does when it is the child.
as_helper! : List(Str) => Try({}, _)
as_helper! = |args|
	match args {
		["print", text] => Stdout.line!(text)
		["both", out, err] => {
			Stdout.line!(out)?
			Stderr.line!(err)
		}
		["exit", code] => {
			Stdout.line!("out")?
			Stderr.line!("err")?
			Err(Exit(I32.from_str(code) ?? 99))
		}
		["hang"] => {
			Stdout.line!("Hi")?
			Sleep.millis!(30_000)?
			Ok({})
		}
		["hang-silently"] => {
			Sleep.millis!(30_000)?
			Ok({})
		}
		["flood"] => {
			for _ in List.repeat(0, 4096) {
				Stdout.write_bytes!("0123456789abcdef".to_utf8())?
			}
			Ok({})
		}
		["large-block"] => Stdout.write_bytes!(List.repeat('x', 65_536))
		["echo"] => Stdout.write_bytes!(Stdin.read_to_end!()?)
		["env", name] =>
			match Env.var!(OsStr.from_str(name)) {
				Ok(value) => Stdout.line!("${name}=${OsStr.display(value)}")
				Err(_) => Stdout.line!("${name} is not set")
			}
		["cwd"] => Stdout.line!(Path.display(Path.canonicalize!(Env.cwd!()?)?))
		["bytes"] => Stdout.write_bytes!([72, 255, 10])
		other => Err(UnknownHelper(other))
	}

## This executable, run as the helper with the given arguments.
helper! : List(Str) => Cmd.Command
helper! = |args| {
	executable = match Env.exe_path!() {
		Ok(path) => Path.to_os_str(path)
		Err(_) => "cmd-api-could-not-find-itself"
	}
	# An empty value turns off the child's own live-handle report, which
	# scripts/test.py requests from this process, so captured stderr is only
	# what the helper wrote.
	Cmd.new(executable)
		.arg("--helper")
		.args(args.map(OsStr.from_str))
		.env("BASIC_CLI_LIVE_HANDLES", "")
}

missing : () -> Cmd.Command
missing = || Cmd.new("definitely-not-a-real-command-xyz").arg("--version")

## Compact functions and builder methods have distinct first-class signatures.
compact! : () => Try({}, _)
compact! = || {
	program = Env.exe_path!()?.to_os_str()
	call! = Cmd.call!
	capture! = Cmd.capture!
	run! = Cmd.run!
	spawn! = Cmd.spawn!
	call!(program, ["--helper", "print", "compact: inherited output"])?
	text = capture!(program, ["--helper", "print", "spaces $HOME *.roc stay literal"])?
	check!("compact capture preserves literal arguments", text == "spaces $HOME *.roc stay literal\n")?
	output = run!(program, ["--helper", "exit", "7"])?
	check!("compact run returns unsuccessful status as data", output.status == Exited(7))?
	child = spawn!(program, ["--helper", "print", "compact: spawned output"])?
	check!("compact spawn returns a waitable child", child.wait!()?.status == Exited(0))?
	check!("compact calls preserve open error rows", call!("definitely-not-a-real-command-xyz", []) == Err(CmdErr(StartFailed(NotFound, "definitely-not-a-real-command-xyz"))))?
	Ok({})
}

## Render a value on one line, with a carriage return shown as `\r`.
show = |value| Str.inspect(value).replace_each("\r", "\\r")

check! : Str, Bool => Try({}, [CheckFailed(Str)])
check! = |name, passed|
	if passed {
		Ok({})
	} else {
		Err(CheckFailed(name))
	}

## The four ways to run a command, and the streams each one leaves unset.
running! : () => Try({}, _)
running! = || {
	# `exec!` inherits: the child's line is part of this program's output.
	helper!(["print", "exec: printed by the child"]).call!()?

	text = helper!(["print", "Hi"]).capture!()?
	check!("capture! returns what was printed", text == "Hi\n")?
	Stdout.line!("capture: ${text.trim()}")?

	# `capture!` leaves stderr on the terminal.
	quiet = helper!(["both", "captured", "capture: stderr reaches the terminal"]).capture!()?
	check!("capture! does not capture stderr", quiet == "captured\n")?

	output = helper!(["both", "to stdout", "to stderr"]).run!()?
	Stdout.line!("run: ${show(output.status)} ${show(output.stdout_utf8_lossy())} ${show(output.stderr_utf8_lossy())}")?
	check!("run! records the command", output.command.ends_with(" --helper both \"to stdout\" \"to stderr\""))?

	# A non-zero exit is data for `run!`, and an error once success is required.
	failed = helper!(["exit", "3"]).run!()?
	check!("run! returns a non-zero status", failed.status == Exited(3))?
	check!("require_success rejects it", failed.require_success() == Err(BadExitStatus(failed)))?
	# The command is masked in its inspected form: a Windows path has
	# backslashes, which `Str.inspect` escapes.
	Stdout.line!("bad exit: ${show(failed.require_success()).replace_each(show(failed.command), show("<command>"))}")?

	match helper!(["exit", "4"]).stdout(Capture).stderr(Capture).call!() {
		Err(BadExitStatus(bad)) => Stdout.line!("exec: ${show(bad.status)} ${show(bad.stdout_utf8_lossy())}")?
		other => {
			return Err(ExpectedBadExitStatus(show(other)))
		}
	}
	match helper!(["exit", "5"]).stderr(Null).capture!() {
		Err(BadExitStatus(bad)) => Stdout.line!("capture: ${show(bad.status)} ${show(bad.stdout_utf8_lossy())}")?
		other => {
			return Err(ExpectedBadExitStatus(show(other)))
		}
	}

	# The exit status of a command that prints to the terminal.
	status = helper!(["print", "inherit_stdio: printed by the child"]).inherit_stdio().run!()?.status
	Stdout.line!("inherit_stdio: ${show(status)}")?

	bytes = helper!(["bytes"]).run!()?.require_success()?.stdout_bytes
	check!("output bytes are exact", bytes == [72, 255, 10])?
	Stdout.line!("bad utf8: ${show(helper!(["bytes"]).capture!())}")?
	Stdout.line!("lossy: ${show(helper!(["bytes"]).run!()?)}".replace_each(show(helper!(["bytes"]).to_str()), show("<command>")))?

	# Two runs of one command give equal outputs.
	first = helper!(["print", "same"]).run!()?
	second = helper!(["print", "same"]).run!()?
	check!("outputs compare by content", first == second and first != output)?

	Stdout.line!("running: ok")
}

## The errors, what they print, and what they leave out.
errors! : () => Try({}, _)
errors! = || {
	secret = "hunter2"
	started = missing().env("API_TOKEN", "hunter2").run!()
	Stdout.line!("missing program: ${show(started)}")?
	check!("a missing program is StartFailed(NotFound, program)", started == Err(CmdErr(StartFailed(NotFound, "definitely-not-a-real-command-xyz"))))?
	check!("errors compare by content", started != Err(CmdErr(StartFailed(PermissionDenied, "definitely-not-a-real-command-xyz"))) and started != Err(CmdErr(IOErr(NotFound))))?
	match started {
		Err(CmdErr(err)) => Stdout.line!("missing program, in words: ${err.to_str()}")?
		Err(Interrupted) => {
			return Err(Interrupted)
		}
		Ok(_) => {}
	}
	match missing().spawn!() {
		Err(CmdErr(StartFailed(NotFound, program))) => Stdout.line!("missing program, spawned: ${OsStr.display(program)}")?
		_ => {
			return Err(ExpectedStartFailed)
		}
	}

	# The child sees the variable; nothing printed about the command shows it.
	with_secret = helper!(["env", "API_TOKEN"]).env("API_TOKEN", "hunter2")
	check!("the child receives the variable", with_secret.capture!()? == "API_TOKEN=hunter2\n")?
	failing = helper!(["exit", "3"]).env("API_TOKEN", "hunter2")
	texts = [
		show(started),
		show(failing),
		failing.to_str(),
		show(failing.run!()),
		show(failing.run!()?.require_success()),
		show(failing.timeout(Duration.zero).run!()),
		show(failing.output_limit(MaxBytes(1)).run!()),
	]
	check!("no rendering contains an environment value", !texts.any(|rendered| rendered.contains(secret)))?
	check!("inspecting a command names its variables", show(failing).contains("OsStr.utf8(\"API_TOKEN\")"))?
	Stdout.line!("environment values: hidden")?

	limited = helper!(["print", "Hello, world"]).output_limit(MaxBytes(4)).run!()
	Stdout.line!("output limit: ${show(limited)}")?
	check!("the limit error carries the output up to the limit", limited == Err(CmdErr(OutputLimitExceeded({ stdout_bytes: [72, 101, 108, 108], stderr_bytes: [] }))))?
	unlimited = helper!(["print", "Hello, world"]).output_limit(NoLimit).run!()?
	check!("NoLimit captures everything", unlimited.stdout_bytes.len() == 13)?

	Stdout.line!("errors: ok")
}

## Stream modes, the working directory, and `Pipe` where no child is returned.
streams! : () => Try({}, _)
streams! = || {
	merged = helper!(["both", "out", "err"]).stderr(MergeWithStdout).run!()?
	Stdout.line!("merged: ${show(merged.stdout_utf8_lossy())} ${show(merged.stderr_utf8_lossy())}")?

	discarded = helper!(["both", "out", "err"]).stdout(Null).stderr(Null).run!()?
	check!("Null discards", discarded.stdout_bytes == [] and discarded.stderr_bytes == [])?

	fed = helper!(["echo"]).stdin(Bytes([0, 42, 255])).run!()?
	check!("Bytes feeds stdin and ends it", fed.stdout_bytes == [0, 42, 255])?

	# `Pipe` without a child to hold the other end: an ended input, captured output.
	piped = helper!(["echo"]).stdin(Pipe).stdout(Pipe).stderr(Pipe).run!()?
	check!("Pipe outside spawn! is Null and Capture", piped.status == Exited(0) and piped.stdout_bytes == [])?
	piped_text = helper!(["print", "piped"]).stdout(Pipe).capture!()?
	check!("Pipe outside spawn! captures", piped_text == "piped\n")?

	teed = helper!(["print", "tee: printed and captured"]).stdout(Tee).run!()?
	check!("Tee captures too", teed.stdout_utf8() == Ok("tee: printed and captured\n"))?

	# The helper prints its directory in canonical form, so compare that form.
	directory = Path.canonicalize!(Env.temp_dir!())?
	here = Path.canonicalize!(Env.cwd!()?)?
	moved = helper!(["cwd"]).cwd(Env.temp_dir!()).capture!()?
	stayed = helper!(["cwd"]).capture!()?
	check!("cwd moves only the child", moved.trim() == Path.display(directory) and stayed.trim() == Path.display(here))?
	check!("the parent stays where it was", Path.canonicalize!(Env.cwd!()?)? == here)?

	cleared = helper!(["env", "CMD_TEST_INHERITED"]).capture!()?
	Stdout.line!("inherited environment: ${cleared.trim()}")?

	to_stderr = helper!(["both", "stdout to parent stderr", "captured stderr"])
		.stdout(InheritStderr).stderr(Capture).run!()?
	check!("parent stderr routing does not capture stdout", to_stderr.stdout_bytes.is_empty() and to_stderr.stderr_utf8_lossy() == "captured stderr\n")?
	merged_stderr = helper!(["both", "merged to parent stderr", "and stderr"])
		.stdout(InheritStderr).stderr(MergeWithStdout).run!()?
	check!("merged inherited stderr is not captured", merged_stderr.stdout_bytes.is_empty() and merged_stderr.stderr_bytes.is_empty())?
	uncaptured = helper!(["print", "zero capture limit with inherited streams"])
		.inherit_stdio().output_limit(MaxBytes(0)).run!()?
	check!("inherited streams have no capture budget", uncaptured.stdout_bytes.is_empty() and uncaptured.stderr_bytes.is_empty())?

	Stdout.line!("streams: ok")
}

## A spawned child: its pipes, its state, and what `close!` does to it.
child! : () => Try({}, _)
child! = || {
	echo = helper!(["echo"]).stdin(Pipe).stdout(Pipe).stderr(Capture).spawn!()?
	check!("pid is known without asking again", echo.pid() != 0 and echo.pid() == echo.pid())?
	check!("a child waiting for input is running", echo.poll!()? == Running)?

	# The helper prints only once its input has ended, so nothing is ready
	# yet and a zero wait does not block.
	Stdout.line!("read, zero wait: ${show(echo.read!(Duration.zero))}")?
	Stdout.line!("read, short wait: ${show(echo.read!(Duration.millis(20)))}")?

	echo.write_utf8!("ping ", Duration.seconds(5))?
	echo.write_bytes!([255, 10], Duration.seconds(5))?
	echo.close_stdin!()?
	echo.close_stdin!()?
	Stdout.line!("write after close_stdin!: ${show(echo.write_utf8!("late", Duration.seconds(1)))}")?

	bytes = read_all!(echo, [])?
	check!("piped bytes round-trip", bytes == "ping ".to_utf8().concat([255, 10]))?
	Stdout.line!("read at the end: ${show(echo.read!(Duration.seconds(5)))}")?

	finished = echo.wait!()?
	check!("piped output is not captured", finished.status == Exited(0) and finished.stdout_bytes == [])?
	check!("waiting again gives the same result", echo.wait!()? == finished)?
	check!("poll! reports a finished child", echo.poll!()? == Finished(finished))?
	echo.kill!()?

	pid = echo.pid()
	echo.close!()?
	echo.close!()?
	Stdout.line!("after close!: read ${show(echo.read!(Duration.seconds(1)))}, write ${show(echo.write_utf8!("x", Duration.zero))}, wait ${show(echo.wait!().map_ok(|_| {}))}, poll ${show(echo.poll!().map_ok(|_| {}))}, kill ${show(echo.kill!())}, close_stdin ${show(echo.close_stdin!())}")?
	check!("pid outlives close!", echo.pid() == pid)?

	# Killing is a status, not an error; closing a running child kills it.
	hung = helper!(["hang"]).stdout(Capture).spawn!()?
	hung.kill!()?
	killed = hung.wait!()?
	check!("a killed child did not succeed", killed.status != Exited(0) and killed.require_success() == Err(BadExitStatus(killed)))?
	if is_unix!() {
		check!("a kill is a signal on Unix", killed.status == Signaled(9))?
	}

	abandoned = helper!(["hang"]).stdout(Null).spawn!()?
	abandoned.close!()?
	check!("close! closes a running child", abandoned.poll!().map_ok(|_| {}) == Err(Closed))?

	Stdout.line!("child: ok")
}

read_all! : Cmd.Child, List(U8) => Try(List(U8), _)
read_all! = |child, bytes|
	match child.read!(Duration.seconds(5)) {
		Ok(Stdout(chunk)) => read_all!(child, bytes.concat(chunk))
		Ok(Stderr(_)) => Err(UnexpectedStderr)
		Err(EndOfInput) => Ok(bytes)
		Err(Closed) => Err(UnexpectedClosed)
		Err(CmdErr(err)) => Err(CmdErr(err))
		Err(Interrupted) => Err(Interrupted)
	}

## The command's own deadline, however the command is run.
deadlines! : () => Try({}, _)
deadlines! = || {
	hang = helper!(["hang"]).timeout(Duration.seconds(2))

	ran = hang.run!()
	Stdout.line!("timed out: ${Str.inspect(ran)}")?
	check!("the deadline error carries the output", ran == Err(CmdErr(TimedOut({ stdout_bytes: [72, 105, 10], stderr_bytes: [] }))))?

	# A spawned child is killed at its deadline too, whoever is waiting.
	spawned = hang.stdout(Capture).spawn!()?
	check!("wait! reports the deadline", spawned.wait!() == Err(CmdErr(TimedOut({ stdout_bytes: [72, 105, 10], stderr_bytes: [] }))))?
	check!("poll! reports the deadline", spawned.poll!() == Err(CmdErr(TimedOut({ stdout_bytes: [72, 105, 10], stderr_bytes: [] }))))?
	Stdout.line!("timed out, spawned: ${Str.inspect(spawned.wait!())}")?

	piped = hang.stdout(Pipe).spawn!()?
	check!("output arrives before the deadline", piped.read!(Duration.seconds(5)) == Ok(Stdout([72, 105, 10])))?
	check!("the stream ends at the deadline", piped.read!(Duration.seconds(5)) == Err(EndOfInput))?
	check!("piped output is not in the partial output", piped.wait!() == Err(CmdErr(TimedOut({ stdout_bytes: [], stderr_bytes: [] }))))?

	# Zero is a deadline that has already passed, not the absence of one. The
	# child writes nothing: one that did could get its output in before a slow
	# parent stopped it, and that output would be in the error.
	instant = helper!(["hang-silently"]).timeout(Duration.zero).run!()
	Stdout.line!("zero timeout: ${Str.inspect(instant)}")?
	check!("exec! and capture! have the deadline too", helper!(["hang-silently"]).timeout(Duration.zero).stdout(Null).call!() == Err(CmdErr(TimedOut({ stdout_bytes: [], stderr_bytes: [] }))) and helper!(["hang-silently"]).timeout(Duration.zero).capture!() == Err(CmdErr(TimedOut({ stdout_bytes: [], stderr_bytes: [] }))))?

	unhurried = helper!(["print", "in time"]).timeout(Duration.seconds(60)).capture!()?
	check!("a deadline that is not reached changes nothing", unhurried == "in time\n")?

	# A full pending queue stops a child nobody reads from.
	flooded = helper!(["print", "more than four bytes"]).stdout(Pipe).pending_limit(4).spawn!()?
	check!("pending_limit stops the child", flooded.wait!() == Err(CmdErr(OutputLimitExceeded({ stdout_bytes: [], stderr_bytes: [] }))))?
	check!("what was queued can still be read", flooded.read!(Duration.zero) == Ok(Stdout([109, 111, 114, 101])))?

	Stdout.line!("deadlines: ok")
}

## Every entry point as a function value beside another error, so that its
## error row has to widen. Error rows are closed at the host boundary by
## design; this stops checking if a wrapper forwards one without rebuilding it.
function_values! : () => Try({}, _)
function_values! = || {
	if Env.var_str!("BASIC_CLI_TEST_ANOTHER_ERROR") == Ok("1") {
		return Err(AnotherError)
	}

	exec! = Cmd.Command.call!
	capture! = Cmd.Command.capture!
	run! = Cmd.Command.run!
	spawn! = Cmd.Command.spawn!

	exec!(helper!(["print", "function value: exec"]))?
	text = capture!(helper!(["print", "capture"]))?
	output = run!(helper!(["print", "run"]))?
	child = spawn!(helper!(["echo"]).stdin(Pipe).stdout(Pipe))?

	wait! = Cmd.Child.wait!
	poll! = Cmd.Child.poll!
	kill! = Cmd.Child.kill!
	close! = Cmd.Child.close!
	close_stdin! = Cmd.Child.close_stdin!
	read! = Cmd.Child.read!
	write_bytes! = Cmd.Child.write_bytes!
	write_utf8! = Cmd.Child.write_utf8!

	write_bytes!(child, [102], Duration.seconds(5))?
	write_utf8!(child, "n", Duration.seconds(5))?
	close_stdin!(child)?
	chunk = read!(child, Duration.seconds(5))?
	finished = wait!(child)?
	state = poll!(child)?
	kill!(child)?
	close!(child)?

	require_success = Cmd.Output.require_success
	stdout_utf8 = Cmd.Output.stdout_utf8
	checked = require_success(output)?
	run_text = stdout_utf8(checked)?

	# `BadUtf8` comes from a builtin; widened by `?` beside other errors it
	# still has to arrive as `BadUtf8`.
	Stdout.line!("bad utf8 through ?: ${show(utf8_through_try!())} ${show(capture_through_try!())}")?

	check!("function values work", text == "capture\n" and run_text == "run\n" and chunk == Stdout([102, 110]) and state == Finished(finished))?
	Stdout.line!("function values: ok")
}

utf8_through_try! : () => Try(Str, _)
utf8_through_try! = || {
	output = helper!(["bytes"]).run!()?
	text = output.stdout_utf8()?
	if text.is_empty() {
		return Err(AnotherError)
	}
	Ok(text)
}

capture_through_try! : () => Try(Str, _)
capture_through_try! = || {
	text = helper!(["bytes"]).capture!()?
	if text.is_empty() {
		return Err(AnotherError)
	}
	Ok(text)
}

is_unix! = || match System.target!().os() {
	Windows(_) => False
	Linux(_) | MacOS(_) => True
}

## File descriptors are opened once before spawn, without capture budgets.
file_outputs! : () => Try({}, _)
file_outputs! = || Env.with_temp_dir!(
	|directory| {
		log = directory.join("server.log")
		result = helper!(["both", "out", "err"])
			.cwd(directory)
			.stdout(File("server.log", RequireNew, { create_permissions: OwnerOnly }))
			.stderr(MergeWithStdout)
			.output_limit(MaxBytes(1))
			.pending_limit(1)
			.spawn!()?.wait!()?.require_success()?
		check!("file stdout is not captured", result.stdout_bytes.is_empty() and result.stderr_bytes.is_empty())?
		check!("merged stderr shares the stdout file and offset", log.read_utf8!()? == "out\nerr\n")?
		helper!(["print", "append"]).stdout(File(log, Append, {})).call!()?
		check!("file append preserves contents", log.read_utf8!()? == "out\nerr\nappend\n")?
		helper!(["print", "truncate"]).stdout(File(log, Truncate, {})).call!()?
		check!("file truncate replaces contents", log.read_utf8!()? == "truncate\n")?
		blocked = helper!(["print", "must not run"]).stdout(File(log, RequireNew, {})).run!()
		match blocked {
			Err(CmdErr(StartFailed(AlreadyExists, _))) => {}
			_ => return Err(CheckFailed("RequireNew must reject an existing output"))
		}
		check!("failed redirect leaves existing file intact", log.read_utf8!()? == "truncate\n")?
		separate = directory.join("stderr.log")
		captured = helper!(["both", "captured", "redirected"]).stdout(Capture).stderr(File(separate, RequireNew, {})).run!()?.require_success()?
		check!("stderr file with captured stdout", captured.stdout_bytes == "captured\n".to_utf8() and captured.stderr_bytes.is_empty() and separate.read_utf8!()? == "redirected\n")?
		large = directory.join("large.log")
		_large_output = helper!(["flood"]).stdout(File(large, RequireNew, {})).output_limit(MaxBytes(1)).pending_limit(1).spawn!()?.wait!()?.require_success()?
		check!("file output does not consume capture or pending budgets", large.read_bytes!()? == List.repeat("0123456789abcdef".to_utf8(), 4096).join())?
		_large_block = helper!(["large-block"]).stdout(File(large, Truncate, {})).output_limit(MaxBytes(1)).pending_limit(1).spawn!()?.wait!()?.require_success()?
		check!("large file writes preserve every byte", large.read_bytes!()? == List.repeat('x', 65_536))?
		Ok({})
	},
)
