import IOErr
import Host
import Resource
import OsStr
import Env
import System
import Path
import Duration

## Build and run child processes with native-safe programs, arguments, and
## environment values.
##
## There are four ways to run a command:
##
## - [call!] runs it on your terminal and requires it to succeed.
## - [capture!] requires it to succeed and returns what it printed, as text.
## - [run!] returns the exit status and the captured output as data.
## - [spawn!] starts it and returns a [Child] to wait on, read from and write to.
##
## ```roc
## Cmd.new("cargo").args(["build", "--release"]).call!()?
##
## sha = Cmd.new("git").args(["rev-parse", "HEAD"]).capture!()?.trim()
##
## output = Cmd.new("roc").arg("version").timeout(Duration.seconds(5)).run!()?
## match output.status {
## 	Exited(0) => Stdout.write_bytes!(output.stdout_bytes)
## 	Exited(code) => Err(CommandFailed(code))
## 	Signaled(signal) => Err(CommandSignaled(signal))
## }
## ```
##
## A caught signal returns `Err(Interrupted)`. Foreground operations kill and
## reap their child before returning; captured output is discarded. A spawned
## child remains under caller control when its read, write or wait is interrupted.
##
## Programs and arguments are passed to the operating system as they are: no
## shell is involved, so spaces, `$FOO` and `*.txt` stay literal.
##
## Errors, [Command.to_str] and `Str.inspect` never contain the value of an environment
## variable, so a command that carries a secret can be logged.
Cmd :: [].{

	## Where the child's standard input comes from.
	##
	## - `Inherit`: the parent's standard input.
	## - `Null`: an input that is already at its end.
	## - `Bytes(bytes)`: the given bytes, after which the input ends.
	## - `Pipe`: a pipe written with [Child.write_bytes!] and ended with
	##   [Child.close_stdin!]. Only [spawn!] returns a [Child], so with [call!],
	##   [capture!] and [run!] it means `Null`.
	StdinMode : [Inherit, Null, Bytes(List(U8)), Pipe]

	## Where the child's standard output goes.
	##
	## - `Inherit`: the parent's standard output.
	## - `InheritStderr`: the parent's standard error, without capturing it.
	## - `Null`: discarded.
	## - `Capture`: kept in memory and returned in the [Output].
	## - `Tee`: captured and also forwarded to the parent's standard output. The
	##   child sees a pipe, not a terminal.
	## - `Pipe`: queued as chunks for [Child.read!]. Only [spawn!] returns a
	##   [Child], so with [call!], [capture!] and [run!] it means `Capture`.
	StdoutMode : [Inherit, InheritStderr, Null, Capture, Tee, Pipe]

	## Where the child's standard error goes: the modes of [StdoutMode], or
	## `MergeWithStdout`, which sends it into the same OS pipe as standard output.
	## That keeps the order in which the child wrote to the two streams, which two
	## separate streams cannot. The merged stream follows the standard output
	## mode and is reported as standard output.
	StderrMode : [Inherit, Null, Capture, Tee, Pipe, MergeWithStdout]

	## How a child ended: `Exited(code)` with its exit code, or `Signaled(signal)`
	## when a signal terminated it. `Signaled` is reported on Unix only.
	ExitStatus : [Exited(I32), Signaled(I32)]

	## The output captured before a deadline or an output limit stopped a command.
	PartialOutput : { stdout_bytes : List(U8), stderr_bytes : List(U8) }

	## Create a new command with the given program name. Execute it with
	## [call!], [capture!], [run!] or [spawn!].
	##
	## ```roc
	## cmd = Cmd.new("ls")
	## ```
	##
	## The program is an [OsStr]. A string literal can be passed directly, and so
	## can a literal that interpolates: `Cmd.new("${tool}")`.
	new : OsStr -> Command
	new = |program| {
		args: [],
		clear_envs: False,
		envs: [],
		program,
		cwd_value: Inherit,
		stdin_value: Unset,
		stdout_value: Unset,
		stderr_value: Unset,
		timeout_value: NoTimeout,
		output_limit_value: MaxBytes(16777216),
		pending_limit_value: 1048576,
		manage_tree_value: False,
	}

	## Run a command with inherited standard streams and require success.
	call! : OsStr, List(OsStr) => Try({}, [CmdErr(Err), BadExitStatus(Output), Interrupted])
	call! = |program, args|
		match new(program).args(args).call!() {
			Ok({}) => Ok({})
			Err(CmdErr(err)) => Err(CmdErr(err))
			Err(Interrupted) => Err(Interrupted)
			Err(BadExitStatus(output)) => Err(BadExitStatus(output))
		}

	## Run a command successfully and return its standard output as text.
	capture! : OsStr, List(OsStr) => Try(Str, [CmdErr(Err), BadExitStatus(Output), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), Interrupted])
	capture! = |program, args|
		match new(program).args(args).capture!() {
			Ok(text) => Ok(text)
			Err(CmdErr(err)) => Err(CmdErr(err))
			Err(Interrupted) => Err(Interrupted)
			Err(BadExitStatus(output)) => Err(BadExitStatus(output))
			Err(BadUtf8(problem)) => Err(BadUtf8(problem))
		}

	## Run a command and return its captured output and exit status.
	run! : OsStr, List(OsStr) => Try(Output, [CmdErr(Err), Interrupted])
	run! = |program, args|
		match new(program).args(args).run!() {
			Ok(output) => Ok(output)
			Err(CmdErr(err)) => Err(CmdErr(err))
			Err(Interrupted) => Err(Interrupted)
		}

	## Start a command with inherited standard streams without waiting.
	spawn! : OsStr, List(OsStr) => Try(Child, [CmdErr(Err), Interrupted])
	spawn! = |program, args|
		match new(program).args(args).spawn!() {
			Ok(child) => Ok(child)
			Err(CmdErr(err)) => Err(CmdErr(err))
			Err(Interrupted) => Err(Interrupted)
		}

	## Replace this Unix process with an executable at an exact pathname.
	##
	## Success never returns and preserves the process ID. The path is relative
	## to the current directory or absolute; there is no PATH search or implicit
	## shell. Arguments, environment, working directory and standard streams
	## keep their native meanings. Arguments do not include the program name.
	##
	## This bypasses Roc cleanup: finish buffered writers, transactions, terminal
	## raw mode and children beforehand when their cleanup matters. Host-owned
	## close-on-exec descriptors close, and other child processes remain alive.
	## A pending caught signal prevents replacement. A returned error leaves the
	## running Roc application available to handle it.
	exec! : System.Unix, Path, List(OsStr) => Try(a, [CmdErr(Err), Interrupted])
	exec! = |unix, executable, args|
		match Host.cmd_exec!(unix, Path.to_raw(executable), args.map(OsStr.to_raw)) {
			Interrupted => Err(Interrupted)
			Failed(error) => Err(CmdErr(StartFailed(error, executable.to_os_str())))
		}

	## A reusable command configuration.
	Command :: {
		args : List(OsStr),
		clear_envs : Bool,
		envs : List((OsStr, OsStr)),
		program : OsStr,
		cwd_value : [Inherit, Dir(Path)],
		stdin_value : [Unset, Set([Inherit, Null, Bytes(List(U8)), Pipe])],
		stdout_value : [Unset, Set([Inherit, InheritStderr, Null, Capture, Tee, Pipe])],
		stderr_value : [Unset, Set([Inherit, Null, Capture, Tee, Pipe, MergeWithStdout])],
		timeout_value : [NoTimeout, After(Duration)],
		output_limit_value : [NoLimit, MaxBytes(U64)],
		pending_limit_value : U64,
		manage_tree_value : Bool,
	}.{

		## Add a single argument to the command.
		## ❗ Shell features like variable substitution (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
		##
		## ```roc
		## cmd = Cmd.new("ls").arg("-l")
		## ```
		arg : Command, OsStr -> Command
		arg = |cmd, a| {
			..cmd,
			args: cmd.args.append(a),
		}

		## Add multiple arguments to the command.
		## ❗ Shell features like variable substitution (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
		##
		## ```roc
		## cmd = Cmd.new("ls").args(["-l", "-a"])
		## ```
		##
		## For a `List(Str)` use `cmd.args(names.map(OsStr.from_str))`.
		args : Command, List(OsStr) -> Command
		args = |cmd, new_args| {
			..cmd,
			args: cmd.args.concat(new_args),
		}

		## Add a single environment variable to the command.
		##
		## ```roc
		## cmd = Cmd.new("env").env("FOO", "bar") # add the environment variable "FOO" with value "bar"
		## ```
		env : Command, OsStr, OsStr -> Command
		env = |cmd, key, value| {
			{ ..cmd, envs: cmd.envs.append((key, value)) }
		}

		## Add multiple environment variables to the command.
		##
		## ```roc
		## cmd = Cmd.new("env").envs([("FOO", "bar"), ("BAZ", "qux")])
		## ```
		envs : Command, List((OsStr, OsStr)) -> Command
		envs = |cmd, pairs| { ..cmd, envs: cmd.envs.concat(pairs) }

		## Clear all environment variables before running the command.
		## Only environment variables added via `env` or `envs` will be available.
		## Useful if you want a clean command run that does not behave unexpectedly if the user has some env var set.
		##
		## ```roc
		## cmd =
		##     Cmd.new("env")
		##         .clear_envs()
		##         .env("ONLY_THIS", "visible")
		## ```
		clear_envs : Command -> Command
		clear_envs = |cmd| { ..cmd, clear_envs: True }

		## Set the child working directory without changing the parent directory.
		## Use an absolute executable path or a bare PATH name: resolving a relative
		## executable against cwd is platform-specific.
		cwd : Command, Path -> Command
		cwd = |cmd, path| { ..cmd, cwd_value: Dir(path) }

		## Choose the child's standard input; see [StdinMode].
		##
		## When this is not called, [run!] gives the child `Null`, and [call!],
		## [capture!] and [spawn!] let it inherit the parent's standard input.
		stdin : Command, StdinMode -> Command
		stdin = |cmd, mode| { ..cmd, stdin_value: Set(mode) }

		## Choose where the child's standard output goes; see [StdoutMode].
		##
		## When this is not called, [run!] and [capture!] capture it, and [call!] and
		## [spawn!] let it go to the parent's standard output.
		stdout : Command, StdoutMode -> Command
		stdout = |cmd, mode| { ..cmd, stdout_value: Set(mode) }

		## Choose where the child's standard error goes; see [StderrMode].
		##
		## When this is not called, [run!] captures it, and [call!], [capture!] and
		## [spawn!] let it go to the parent's standard error.
		stderr : Command, StderrMode -> Command
		stderr = |cmd, mode| { ..cmd, stderr_value: Set(mode) }

		## Let the child use the parent's standard input, output and error, however
		## the command is run. With [run!] this gives the exit status of a command
		## that prints to the terminal:
		##
		## ```roc
		## status = Cmd.new("roc").args(["check", "main.roc"]).inherit_stdio().run!()?.status
		## ```
		inherit_stdio : Command -> Command
		inherit_stdio = |cmd| { ..cmd, stdin_value: Set(Inherit), stdout_value: Set(Inherit), stderr_value: Set(Inherit) }

		## Stop the command when it has run for longer than `duration`. The deadline
		## covers the whole run, including reading the rest of its output.
		##
		## A command that reaches its deadline is killed, and the result is
		## `Err(CmdErr(TimedOut(partial)))` with the output captured so far. That is
		## also what [Child.wait!] and [Child.poll!] return for a child started with
		## [spawn!]. When `timeout` is not called there is no deadline;
		## `Duration.zero` expires immediately.
		timeout : Command, Duration -> Command
		timeout = |cmd, duration| { ..cmd, timeout_value: After(duration) }

		## Limit how many bytes of standard output and standard error are captured,
		## counted together. The default is `MaxBytes(16777216)`, 16 MiB.
		##
		## A command that prints more is killed, and the result is
		## `Err(CmdErr(OutputLimitExceeded(partial)))` with the output captured up to
		## the limit. `NoLimit` captures whatever the command prints.
		output_limit : Command, [NoLimit, MaxBytes(U64)] -> Command
		output_limit = |cmd, limit| { ..cmd, output_limit_value: limit }

		## Limit how many bytes of `Pipe` output may wait to be read with
		## [Child.read!], counted over both streams (default 1 MiB). A child that
		## gets further ahead of its reader is killed, and [Child.wait!] returns
		## `Err(CmdErr(OutputLimitExceeded(partial)))`.
		pending_limit : Command, U64 -> Command
		pending_limit = |cmd, bytes| { ..cmd, pending_limit_value: bytes }

		## Also terminate descendants on cancellation, using a Unix process group
		## or Windows Job Object. Disabled by default; descendants must not escape it.
		manage_tree : Command, Bool -> Command
		manage_tree = |cmd, enabled| { ..cmd, manage_tree_value: enabled }

		# A tag union that crosses the host boundary is closed by design, so the
		# four entry points below, like the `Child` methods, rebuild the error they
		# forward from the host. That gives callers an open union, which `?` can
		# combine with other error types however the function is called.
		# `tests/cmd-api.roc` covers the function-value form.

		## Run the command on the parent's terminal and require it to succeed.
		##
		## Standard input, output and error are inherited unless the command sets
		## them. Any status other than exit code 0 is `Err(BadExitStatus(output))`.
		##
		## ```roc
		## Cmd.new("cargo").args(["build", "--release"]).call!()?
		## ```
		call! : Command => Try({}, [CmdErr(Err), BadExitStatus(Output), Interrupted])
		call! = |cmd|
			match finish!(cmd, Call) {
				Ok(output) =>
					match output.require_success() {
						Ok(_) => Ok({})
						Err(BadExitStatus(failed)) => Err(BadExitStatus(failed))
					}
				Err(CmdErr(err)) => Err(CmdErr(err))
				Err(Interrupted) => Err(Interrupted)
			}

		## Run the command, require it to succeed, and return its standard output as
		## text.
		##
		## Standard output is captured unless the command sets it. Standard input and
		## standard error are inherited unless the command sets them, so warnings
		## still reach the terminal, as with a shell's `$(..)`. Any status other than
		## exit code 0 is `Err(BadExitStatus(output))`, and output that is not UTF-8
		## is `Err(BadUtf8(..))`.
		##
		## The text is returned as printed, including a final newline:
		##
		## ```roc
		## sha = Cmd.new("git").args(["rev-parse", "${branch}"]).capture!()?.trim()
		## ```
		capture! : Command => Try(Str, [CmdErr(Err), BadExitStatus(Output), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), Interrupted])
		capture! = |cmd|
			match finish!(cmd, Capture) {
				Ok(output) =>
					match output.require_success() {
						Ok(succeeded) =>
							match succeeded.stdout_utf8() {
								Ok(text) => Ok(text)
								Err(BadUtf8(problem)) => Err(BadUtf8(problem))
							}
						Err(BadExitStatus(failed)) => Err(BadExitStatus(failed))
					}
				Err(CmdErr(err)) => Err(CmdErr(err))
				Err(Interrupted) => Err(Interrupted)
			}

		## Run the command and return its exit status and output as data. A non-zero
		## exit code or a signal is not an error here: match on `output.status`, or
		## call [Output.require_success].
		##
		## Standard output and standard error are captured, and standard input is
		## `Null`, unless the command sets them. The result is returned once the
		## command has exited and all of its output has been read.
		##
		## ```roc
		## output = Cmd.new("roc").args(["check", "main.roc"]).run!()?
		## ```
		run! : Command => Try(Output, [CmdErr(Err), Interrupted])
		run! = |cmd|
			match finish!(cmd, Run) {
				Ok(output) => Ok(output)
				Err(CmdErr(err)) => Err(CmdErr(err))
				Err(Interrupted) => Err(Interrupted)
			}

		## Start the command and return a [Child] without waiting for it.
		##
		## Standard input, output and error are inherited unless the command sets
		## them. Set a stream to `Pipe` to exchange data with the child while it runs.
		spawn! : Command => Try(Child, [CmdErr(Err), Interrupted])
		spawn! = |cmd|
			match Host.cmd_spawn!(to_host_cmd(cmd, Spawn)) {
				Ok(handle) =>
					Ok(
						Child.{
							host: handle,
							pid_value: Host.child_pid!(handle),
							command: to_str(cmd),
							program: cmd.program,
						},
					)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, cmd.program)))
				Err(Interrupted) => Err(Interrupted)
			}

		## The program and its arguments, separated by spaces, for messages and logs.
		## An argument that is empty or contains a space or a quote is written as a
		## quoted, escaped string. The environment, the working directory and the
		## other settings are not included.
		##
		## ```roc
		## expect Cmd.new("git").args(["commit", "-m", "first draft"]).to_str() == "git commit -m \"first draft\""
		## ```
		to_str : Command -> Str
		to_str = |cmd|
			Str.join_with([cmd.program].concat(cmd.args).map(display_word), " ")

		## Customize command output for `Str.inspect`: the full configuration, with
		## the names of the environment variables it sets but never their values, and
		## the length of `Bytes` input but not its content.
		to_inspect : Command -> Str
		to_inspect = |cmd| {
			env_names = cmd.envs.map(|(name, _)| name)
			stdin_text =
				match cmd.stdin_value {
					Set(Bytes(bytes)) => "Set(Bytes(<${bytes.len().to_str()} bytes>))"
					other => Str.inspect(other)
				}

			"Cmd.Command({ program: ${Str.inspect(cmd.program)}, args: ${Str.inspect(cmd.args)}, env_names: ${Str.inspect(env_names)}, clear_envs: ${Str.inspect(cmd.clear_envs)}, cwd: ${Str.inspect(cmd.cwd_value)}, stdin: ${stdin_text}, stdout: ${Str.inspect(cmd.stdout_value)}, stderr: ${Str.inspect(cmd.stderr_value)}, timeout: ${Str.inspect(cmd.timeout_value)}, output_limit: ${Str.inspect(cmd.output_limit_value)}, pending_limit: ${Str.inspect(cmd.pending_limit_value)}, manage_tree: ${Str.inspect(cmd.manage_tree_value)} })"
		}
	}

	## Report whether `command` can be found on the system as something runnable.
	##
	## A bare name (like `"git"`) is looked up across the `PATH` entries; a name
	## containing a path separator is checked as-is. On Windows the candidate
	## extensions come from `%PATHEXT%`.
	##
	## On Unix this checks for an executable bit; a directory is not reported even
	## though it carries one, though a symbolic link to a directory is a rare
	## exception.
	check_available! : Str => Bool
	check_available! = |command| {
		is_windows =
			match System.target!().os() {
				Windows(_) => True
				_ => False
			}

		if has_separator(command, is_windows) {
			candidate_available!(Path.utf8(command), is_windows)
		} else {
			path_value =
				match Env.var!(OsStr.from_str("PATH")) {
					Ok(value) => value
					Err(_) => OsStr.from_str("")
				}

			# On Windows a name is tried as-is (so `git.exe` is found directly)
			# and with each `%PATHEXT%` extension appended (so `git` finds
			# `git.exe`). On Unix the name is used verbatim.
			extensions = if is_windows [""].concat(path_extensions!()) else [""]

			search_dirs!(path_dirs(path_value, is_windows), command, extensions, is_windows)
		}
	}

	## Why a command could not be started or did not run to completion. A
	## non-zero exit code is not one of these: it is `BadExitStatus`, or the
	## `status` of an [Output].
	##
	## - `StartFailed(err, program)`: the program could not be started, for
	##   example `StartFailed(NotFound, program)` when it does not exist.
	## - `TimedOut(partial)`: the command reached the deadline set with
	##   [Command.timeout] and was killed.
	## - `OutputLimitExceeded(partial)`: the command printed more than
	##   [Command.output_limit] or [Command.pending_limit] allows and was killed.
	## - `IOErr(err)`: an operating-system failure while the command ran. A
	##   [Child.read!] or [Child.write_bytes!] that waited for its whole
	##   `Duration` is `IOErr(TimedOut)`.
	Err := [StartFailed(IOErr, OsStr), TimedOut(PartialOutput), OutputLimitExceeded(PartialOutput), IOErr(IOErr)].{

		## Compare two errors, so results that contain one work with `==`.
		is_eq : _

		## Describe the error in a sentence, without the captured output.
		to_str : Err -> Str
		to_str = |err|
			match err {
				StartFailed(io_err, program) => "could not start ${display_word(program)}: ${io_err.to_str()}"
				TimedOut(_) => "command timed out"
				OutputLimitExceeded(_) => "command exceeded its output limit"
				IOErr(io_err) => io_err.to_str()
			}

		## Customize error output for `Str.inspect`. Captured output is shown as
		## text, with invalid UTF-8 replaced, not as a list of bytes.
		to_inspect : Err -> Str
		to_inspect = |err|
			match err {
				StartFailed(io_err, program) => "StartFailed(${Str.inspect(io_err)}, ${Str.inspect(program)})"
				TimedOut(partial) => "TimedOut(${inspect_partial(partial)})"
				OutputLimitExceeded(partial) => "OutputLimitExceeded(${inspect_partial(partial)})"
				IOErr(io_err) => "IOErr(${Str.inspect(io_err)})"
			}
	}

	## The result of a command that ran to completion: how it ended and what it
	## printed. `command` is the program and arguments, as [Command.to_str] renders them.
	## Output is empty for a stream that was not captured.
	Output := { command : Str, status : ExitStatus, stdout_bytes : List(U8), stderr_bytes : List(U8) }.{

		## Compare two outputs, so results that contain one work with `==`.
		is_eq : _

		## Turn any status other than exit code 0 into `Err(BadExitStatus(output))`.
		##
		## ```roc
		## bytes = cmd.run!()?.require_success()?.stdout_bytes
		## ```
		require_success : Output -> Try(Output, [BadExitStatus(Output)])
		require_success = |output|
			match output.status {
				Exited(0) => Ok(output)
				_ => Err(BadExitStatus(output))
			}

		## The captured standard output as text, or `BadUtf8` when it is not
		## valid UTF-8.
		stdout_utf8 : Output -> Try(Str, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
		stdout_utf8 = |output|
			# The builtin's one-tag error is rebuilt, so it keeps its tag when
			# `?` widens it beside other errors.
			match Str.from_utf8(output.stdout_bytes) {
				Ok(text) => Ok(text)
				Err(BadUtf8(problem)) => Err(BadUtf8(problem))
			}

		## The captured standard output as text, with invalid UTF-8 replaced by
		## the Unicode replacement character.
		stdout_utf8_lossy : Output -> Str
		stdout_utf8_lossy = |output| Str.from_utf8_lossy(output.stdout_bytes)

		## The captured standard error as text, with invalid UTF-8 replaced by
		## the Unicode replacement character.
		stderr_utf8_lossy : Output -> Str
		stderr_utf8_lossy = |output| Str.from_utf8_lossy(output.stderr_bytes)

		## Customize output for `Str.inspect`. Captured output is shown as text,
		## with invalid UTF-8 replaced, not as a list of bytes.
		to_inspect : Output -> Str
		to_inspect = |output|
			"{ command: ${Str.inspect(output.command)}, status: ${Str.inspect(output.status)}, stdout: ${Str.inspect(Str.from_utf8_lossy(output.stdout_bytes))}, stderr: ${Str.inspect(Str.from_utf8_lossy(output.stderr_bytes))} }"
	}

	## A running command started with [spawn!].
	##
	## When the last reference to a child is released, a child that is still
	## running is killed and reaped. Use [Child.close!] to do that at a chosen
	## point. After `close!` every other operation returns `Err(Closed)`.
	Child :: { host : Resource.Child, pid_value : U32, command : Str, program : OsStr }.{

		# A tag union that crosses the host boundary is closed by design, so
		# every method below rebuilds the error it forwards from the host. That
		# gives callers an open union, which `?` can combine with other error
		# types however the method is called.

		## The operating-system process identifier the child was started with.
		pid : Child -> U32
		pid = |child| child.pid_value

		## Wait for the child to exit and for all of its output to be read, then
		## return its status and captured output. A piped standard input is
		## closed first, so exchange data with [write_bytes!] and [read!] before
		## waiting. Waiting again returns the same result.
		wait! : Child => Try(Output, [CmdErr(Cmd.Err), Closed, Interrupted])
		wait! = |child|
			match Host.child_wait!(child.host) {
				Ok(output) => Ok(from_host_output(output, child.command))
				Err(Closed) => Err(Closed)
				Err(Interrupted) => Err(Interrupted)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Check on the child without waiting: `Running`, or `Finished(output)`
		## once it has exited and all of its output has been read.
		poll! : Child => Try([Running, Finished(Output)], [CmdErr(Cmd.Err), Closed])
		poll! = |child|
			match Host.child_poll!(child.host) {
				Ok(Running) => Ok(Running)
				Ok(Finished(output)) => Ok(Finished(from_host_output(output, child.command)))
				Err(Closed) => Err(Closed)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Ask the operating system to kill the child. This does not wait: use
		## [wait!] to see it end. Killing a child that has exited does nothing.
		kill! : Child => Try({}, [CmdErr(Cmd.Err), Closed])
		kill! = |child|
			match Host.child_kill!(child.host) {
				Ok({}) => Ok({})
				Err(Closed) => Err(Closed)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Close a piped standard input so the child sees the end of its input.
		## Closing it again does nothing.
		close_stdin! : Child => Try({}, [CmdErr(Cmd.Err), Closed])
		close_stdin! = |child|
			match Host.child_close_stdin!(child.host) {
				Ok({}) => Ok({})
				Err(Closed) => Err(Closed)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Kill a child that is still running, reap it, and close the handle for
		## every reference to it. Closing again does nothing.
		close! : Child => Try({}, [CmdErr(Cmd.Err)])
		close! = |child|
			match Host.child_close!(child.host) {
				Ok({}) => Ok({})
				Err(err) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Return the next chunk of `Pipe` output, from whichever stream has
		## one, waiting up to `wait` for it. The host picks the chunk size.
		##
		## `Duration.zero` does not wait: it returns a chunk that is ready, and
		## otherwise times out. A wait that expires is
		## `Err(CmdErr(IOErr(TimedOut)))`; the child keeps running and may be
		## read again. Once the child has exited and every chunk has been
		## returned, the result is `Err(EndOfInput)`.
		##
		## ```roc
		## chunk = child.read!(Duration.seconds(1))?
		## ```
		read! : Child, Duration => Try([Stdout(List(U8)), Stderr(List(U8))], [EndOfInput, CmdErr(Cmd.Err), Closed, Interrupted])
		read! = |child, wait|
			match Host.child_read!(child.host, wait.to_nanos()) {
				Ok(Stdout(bytes)) => Ok(Stdout(bytes))
				Ok(Stderr(bytes)) => Ok(Stderr(bytes))
				Err(EndOfInput) => Err(EndOfInput)
				Err(Closed) => Err(Closed)
				Err(Interrupted) => Err(Interrupted)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Write bytes to a piped standard input, waiting up to `wait` for the
		## child to accept all of them. `Duration.zero` makes one attempt that
		## does not wait.
		##
		## A wait that expires is `Err(CmdErr(IOErr(TimedOut)))`. Part of the
		## input may have been delivered by then, or before `Interrupted`, so writing all of it again can
		## duplicate bytes. Writing when standard input is not a pipe, or after
		## [close_stdin!], is `Err(CmdErr(IOErr(BrokenPipe)))`.
		write_bytes! : Child, List(U8), Duration => Try({}, [CmdErr(Cmd.Err), Closed, Interrupted])
		write_bytes! = |child, bytes, wait|
			match Host.child_write!(child.host, bytes, wait.to_nanos()) {
				Ok({}) => Ok({})
				Err(Closed) => Err(Closed)
				Err(Interrupted) => Err(Interrupted)
				Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, child.program)))
			}

		## Write text to a piped standard input as UTF-8; see [write_bytes!].
		write_utf8! : Child, Str, Duration => Try({}, [CmdErr(Cmd.Err), Closed, Interrupted])
		write_utf8! = |child, text, wait| write_bytes!(child, text.to_utf8(), wait)
	}
}

## Run a command to completion with the stream defaults of one entry point.
finish! : Cmd.Command, [Run, Call, Capture, Spawn] => Try(Cmd.Output, [CmdErr(Cmd.Err), Interrupted])
finish! = |cmd, entry|
	match Host.cmd_run!(to_host_cmd(cmd, entry)) {
		Ok(output) => Ok(from_host_output(output, Cmd.Command.to_str(cmd)))
		Err(CmdErr(err)) => Err(CmdErr(from_host_err(err, cmd.program)))
		Err(Interrupted) => Err(Interrupted)
	}

from_host_output : Host.CmdOutput, Str -> Cmd.Output
from_host_output = |output, command| {
	command,
	status: output.status,
	stdout_bytes: output.stdout_bytes,
	stderr_bytes: output.stderr_bytes,
}

## The host does not know which program a `Cmd` names, so it is added here.
from_host_err : Host.CmdErr, OsStr -> Cmd.Err
from_host_err = |err, program|
	match err {
		StartFailed(io_err) => StartFailed(io_err, program)
		TimedOut(partial) => TimedOut(partial)
		OutputLimitExceeded(partial) => OutputLimitExceeded(partial)
		IOErr(io_err) => IOErr(io_err)
	}

## Captured output as text, so an unhandled error is readable.
inspect_partial : Cmd.PartialOutput -> Str
inspect_partial = |partial|
	"{ stdout: ${Str.inspect(Str.from_utf8_lossy(partial.stdout_bytes))}, stderr: ${Str.inspect(Str.from_utf8_lossy(partial.stderr_bytes))} }"

## A program or argument as one word of a command line: as it is when that is
## unambiguous, otherwise quoted and escaped.
display_word : OsStr -> Str
display_word = |word| {
	text = OsStr.display(word)
	if text.is_empty() or text.contains(" ") or text.contains("\"") or text.contains("\n") or text.contains("\t") {
		Str.inspect(text)
	} else {
		text
	}
}

## Resolve the streams a command did not set, and `Pipe` where no `Child` is
## returned, for the entry point that runs it. The host is given final modes.
to_host_cmd : Cmd.Command, [Run, Call, Capture, Spawn] -> Host.Cmd
to_host_cmd = |cmd, entry| {
	args: cmd.args.map(OsStr.to_raw),
	clear_envs: cmd.clear_envs,
	envs: cmd.envs.join_map(|(name, value)| [name, value]).map(OsStr.to_raw),
	program: OsStr.to_raw(cmd.program),
	cwd: match cmd.cwd_value {
		Inherit => Inherit
		Dir(path) => Dir(Path.to_raw(path))
	},
	stdin: match (cmd.stdin_value, entry) {
		(Unset, Run) => Null
		(Unset, _) => Inherit
		(Set(Pipe), Spawn) => Pipe
		(Set(Pipe), _) => Null
		(Set(mode), _) => mode
	},
	stdout: match (cmd.stdout_value, entry) {
		(Unset, Run) | (Unset, Capture) => Capture
		(Unset, _) => Inherit
		(Set(Pipe), Spawn) => Pipe
		(Set(Pipe), _) => Capture
		(Set(mode), _) => mode
	},
	stderr: match (cmd.stderr_value, entry) {
		(Unset, Run) => Capture
		(Unset, _) => Inherit
		(Set(Pipe), Spawn) => Pipe
		(Set(Pipe), _) => Capture
		(Set(mode), _) => mode
	},
	timeout: match cmd.timeout_value {
		NoTimeout => NoTimeout
		After(duration) => AfterNanos(duration.to_nanos())
	},
	output_limit: cmd.output_limit_value,
	pending_limit: cmd.pending_limit_value,
	manage_tree: cmd.manage_tree_value,
}

## A command name is a path, rather than a bare name, when it carries a separator.
has_separator : Str, Bool -> Bool
has_separator = |command, is_windows|
	command.contains("/") or (is_windows and command.contains("\\"))

## Split the raw `PATH` value into byte-preserving directory paths. Empty entries
## are dropped so a stray separator does not resolve to the filesystem root.
path_dirs : OsStr, Bool -> List(Path)
path_dirs = |path_value, is_windows|
	match OsStr.to_raw(path_value) {
		Utf8(str) =>
			Str.split_on(str, if is_windows ";" else ":")
				.keep_if(|segment| !Str.is_empty(segment))
				.map(Path.utf8)

		UnixBytes(bytes) =>
			bytes.split_on(if is_windows ';' else ':')
				.keep_if(|segment| !List.is_empty(segment))
				.map(Path.unix_bytes)

		WindowsU16s(u16s) =>
			u16s.split_on(if is_windows ';' else ':')
				.keep_if(|segment| !List.is_empty(segment))
				.map(Path.windows_u16s)
	}

## The executable extensions to try on Windows, taken from `%PATHEXT%`.
path_extensions! : () => List(Str)
path_extensions! = ||
	match Env.var!(OsStr.from_str("PATHEXT")) {
		Ok(value) =>
			Str.split_on(OsStr.display(value), ";")
				.keep_if(|ext| !Str.is_empty(ext))
		Err(_) => [".com", ".exe", ".bat", ".cmd"]
	}

## Search each directory for the command, returning on the first executable hit.
search_dirs! : List(Path), Str, List(Str), Bool => Bool
search_dirs! = |dirs, command, extensions, is_windows|
	match dirs {
		[] => False
		[dir, .. as rest] =>
			if search_extensions!(dir, command, extensions, is_windows) {
				True
			} else {
				search_dirs!(rest, command, extensions, is_windows)
			}
	}

search_extensions! : Path, Str, List(Str), Bool => Bool
search_extensions! = |dir, command, extensions, is_windows|
	match extensions {
		[] => False
		[ext, .. as rest] =>
			if candidate_available!(dir.join(command.concat(ext)), is_windows) {
				True
			} else {
				search_extensions!(dir, command, rest, is_windows)
			}
	}

## Whether a specific candidate path is runnable: on Windows it must exist, on
## Unix it must carry an executable bit. Either way a directory is rejected,
## since a directory both exists and carries an executable bit.
candidate_available! : Path, Bool => Bool
candidate_available! = |candidate, is_windows| {
	runnable = if is_windows Path.exists!(candidate) else Path.is_executable!(candidate)
	match runnable {
		Ok(True) => not_directory!(candidate)
		Ok(False) => False
		Err(_) => False
	}
}

## `is_dir!` does not follow symlinks, so a symlink to an executable is kept while
## a real directory is rejected. A symlink pointing at a directory is not caught.
not_directory! : Path => Bool
not_directory! = |candidate|
	match Path.is_dir!(candidate) {
		Ok(is_dir) => !is_dir
		Err(_) => True
	}

## `to_str` is the program and its arguments, quoted only where needed.
expect Cmd.new("git").args(["rev-parse", "HEAD"]).to_str() == "git rev-parse HEAD"
expect Cmd.new("git").args(["commit", "-m", "first draft", ""]).to_str() == "git commit -m \"first draft\" \"\""

## Neither rendering contains the value of an environment variable, or the
## bytes given as standard input.
expect {
	cmd = Cmd.new("deploy")
		.arg("now")
		.env("API_TOKEN", "hunter2")
		.envs([("REGION", "eu-west-1")])
		.stdin(Bytes("hunter2".to_utf8()))
		.clear_envs()

	Str.inspect(cmd) == "Cmd.Command({ program: OsStr.utf8(\"deploy\"), args: [OsStr.utf8(\"now\")], env_names: [OsStr.utf8(\"API_TOKEN\"), OsStr.utf8(\"REGION\")], clear_envs: True, cwd: Inherit, stdin: Set(Bytes(<7 bytes>)), stdout: Unset, stderr: Unset, timeout: NoTimeout, output_limit: MaxBytes(16777216), pending_limit: 1048576, manage_tree: False })"
}
expect {
	cmd = Cmd.new("deploy").env("API_TOKEN", "hunter2")
	!Str.inspect(cmd).contains("hunter2") and !cmd.to_str().contains("hunter2")
}

## A builder call replaces the earlier setting of the same stream.
expect {
	cmd = Cmd.new("tool").stdout(Null).inherit_stdio().stderr(MergeWithStdout).timeout(Duration.seconds(5)).output_limit(NoLimit)
	Str.inspect(cmd).contains("stdin: Set(Inherit), stdout: Set(Inherit), stderr: Set(MergeWithStdout), timeout: After(Duration(5s)), output_limit: NoLimit")
}

## Streams a command did not set follow the entry point that runs it.
expect {
	host = to_host_cmd(Cmd.new("tool"), Run)
	host.stdin == Null and host.stdout == Capture and host.stderr == Capture
}
expect {
	host = to_host_cmd(Cmd.new("tool"), Call)
	host.stdin == Inherit and host.stdout == Inherit and host.stderr == Inherit
}
expect {
	host = to_host_cmd(Cmd.new("tool"), Capture)
	host.stdin == Inherit and host.stdout == Capture and host.stderr == Inherit
}
expect {
	host = to_host_cmd(Cmd.new("tool"), Spawn)
	host.stdin == Inherit and host.stdout == Inherit and host.stderr == Inherit
}

## `Pipe` needs a `Child`: only `spawn!` passes it on.
expect {
	cmd = Cmd.new("tool").stdin(Pipe).stdout(Pipe).stderr(Pipe)
	spawned = to_host_cmd(cmd, Spawn)
	ran = to_host_cmd(cmd, Run)
	executed = to_host_cmd(cmd, Call)
	spawned.stdin == Pipe and spawned.stdout == Pipe and spawned.stderr == Pipe and ran.stdin == Null and ran.stdout == Capture and ran.stderr == Capture and executed.stdin == Null and executed.stdout == Capture and executed.stderr == Capture
}

## A stream that was set is passed on as it is.
expect {
	host = to_host_cmd(Cmd.new("tool").stdin(Bytes([1, 2])).stdout(Tee).stderr(MergeWithStdout), Run)
	host.stdin == Bytes([1, 2]) and host.stdout == Tee and host.stderr == MergeWithStdout
}

## The deadline and the limits cross as typed values, and zero is a deadline.
expect {
	host = to_host_cmd(Cmd.new("tool"), Run)
	host.timeout == NoTimeout and host.output_limit == MaxBytes(16777216) and host.cwd == Inherit
}
expect {
	host = to_host_cmd(Cmd.new("tool").timeout(Duration.zero).output_limit(NoLimit).cwd(Path.utf8("/tmp")), Run)
	host.timeout == AfterNanos(0) and host.output_limit == NoLimit and host.cwd == Dir(Utf8("/tmp"))
}

## Only exit code 0 is success.
expect {
	output : Cmd.Output
	output = { command: "true", status: Exited(0), stdout_bytes: [], stderr_bytes: [] }
	output.require_success() == Ok(output)
}
expect {
	output : Cmd.Output
	output = { command: "false", status: Exited(1), stdout_bytes: [], stderr_bytes: [] }
	output.require_success() == Err(BadExitStatus(output))
}
expect {
	output : Cmd.Output
	output = { command: "sleep 30", status: Signaled(9), stdout_bytes: [], stderr_bytes: [] }
	output.require_success() == Err(BadExitStatus(output))
}

## Output is text when it is UTF-8, and lossy text on request.
expect {
	output : Cmd.Output
	output = { command: "echo Hi", status: Exited(0), stdout_bytes: [72, 105, 10], stderr_bytes: [255] }
	output.stdout_utf8() == Ok("Hi\n") and output.stdout_utf8_lossy() == "Hi\n" and output.stderr_utf8_lossy() == "\u(FFFD)"
}
expect {
	output : Cmd.Output
	output = { command: "tool", status: Exited(0), stdout_bytes: [72, 255], stderr_bytes: [] }
	match output.stdout_utf8() {
		Err(BadUtf8({ index, .. })) => index == 1
		Ok(_) => False
	}
}

## An output prints its bytes as text.
expect {
	output : Cmd.Output
	output = { command: "echo Hi", status: Exited(0), stdout_bytes: [72, 105, 10], stderr_bytes: [] }
	Str.inspect(output) == "{ command: \"echo Hi\", status: Exited(0), stdout: \"Hi\n\", stderr: \"\" }"
}

## An unhandled error prints captured output as text.
expect {
	result : Try({}, [CmdErr(Cmd.Err)])
	result = Err(CmdErr(TimedOut({ stdout_bytes: [72, 105, 10], stderr_bytes: [] })))
	Str.inspect(result) == "Err(CmdErr(TimedOut({ stdout: \"Hi\n\", stderr: \"\" })))"
}
expect {
	err : Cmd.Err
	err = OutputLimitExceeded({ stdout_bytes: [97, 255], stderr_bytes: [98] })
	Str.inspect(err) == "OutputLimitExceeded({ stdout: \"a\u(FFFD)\", stderr: \"b\" })"
}
expect {
	err : Cmd.Err
	err = StartFailed(NotFound, "no-such-tool")
	Str.inspect(err) == "StartFailed(NotFound, OsStr.utf8(\"no-such-tool\"))" and err.to_str() == "could not start no-such-tool: entity was not found"
}
expect {
	err : Cmd.Err
	err = IOErr(TimedOut)
	Str.inspect(err) == "IOErr(TimedOut)" and err.to_str() == "operation timed out"
}
expect {
	timed_out : Cmd.Err
	timed_out = TimedOut({ stdout_bytes: [], stderr_bytes: [] })
	limited : Cmd.Err
	limited = OutputLimitExceeded({ stdout_bytes: [], stderr_bytes: [] })
	timed_out.to_str() == "command timed out" and limited.to_str() == "command exceeded its output limit"
}

## Errors and outputs compare by content.
expect {
	left : Try(Cmd.Output, [CmdErr(Cmd.Err)])
	left = Err(CmdErr(StartFailed(NotFound, "tool")))
	left == Err(CmdErr(StartFailed(NotFound, "tool"))) and left != Err(CmdErr(StartFailed(PermissionDenied, "tool"))) and left != Err(CmdErr(IOErr(NotFound)))
}
expect {
	left : Cmd.Err
	left = TimedOut({ stdout_bytes: [1], stderr_bytes: [] })
	right : Cmd.Err
	right = TimedOut({ stdout_bytes: [2], stderr_bytes: [] })
	left != right
}
expect {
	left : Cmd.Output
	left = { command: "a", status: Exited(0), stdout_bytes: [1], stderr_bytes: [] }
	right : Cmd.Output
	right = { command: "a", status: Exited(1), stdout_bytes: [1], stderr_bytes: [] }
	left != right and left == left
}

## A name is a path only when it carries a separator for the current platform.
expect has_separator("git", False) == False
expect has_separator("./git", False) == True
expect has_separator("a\\b", False) == False
expect has_separator("a\\b", True) == True

## Splitting keeps every segment, including a trailing empty one after a separator.
expect [1.U8, 2, 58, 3].split_on(58) == [[1, 2], [3]]
expect [59.U16, 1, 59].split_on(59) == [[], [1], []]

## PATH splitting preserves raw bytes, including non-UTF-8 directory entries.
expect {
	# "/a" ++ ":" ++ "/<0xFF>b" — the 0xFF byte is not valid UTF-8.
	path = OsStr.unix_bytes([0x2F, 0x61, 0x3A, 0x2F, 0xFF, 0x62])
	path_dirs(path, False) == [Path.unix_bytes([0x2F, 0x61]), Path.unix_bytes([0x2F, 0xFF, 0x62])]
}

## The UTF-8 PATH representation splits the same way.
expect path_dirs(OsStr.utf8("/a:/b"), False) == [Path.utf8("/a"), Path.utf8("/b")]

## Empty PATH entries (a stray or trailing separator) are dropped, not resolved to root.
expect path_dirs(OsStr.utf8("/a::/b:"), False) == [Path.utf8("/a"), Path.utf8("/b")]

## Windows PATH splits on ';' and preserves UTF-16 units.
expect {
	path = OsStr.windows_u16s([0x43, 0x3B, 0x44])
	path_dirs(path, True) == [Path.windows_u16s([0x43]), Path.windows_u16s([0x44])]
}
