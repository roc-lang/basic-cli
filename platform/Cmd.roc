import IOErr exposing [IOErr]
import Host
import OsStr exposing [OsStr]
import Env
import Path exposing [Path]

## Build and run child processes with native-safe programs, arguments, and
## environment values.
Cmd :: {
	args : List(OsStr),
	clear_envs : Bool,
	envs : List((OsStr, OsStr)),
	program : OsStr,
}.{

	## Simplest way to execute a command by name with arguments.
	## Stdin, stdout, and stderr are inherited from the parent process.
	##
	## If you want to capture the output, use [exec_output!] instead.
	##
	## ```roc
	## Cmd.exec!("echo", ["hello world"])?
	## ```
	exec! : OsStr, List(OsStr) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec! = |program, arguments| {
		command = "${OsStr.display(program)} ${Str.join_with(arguments.map(OsStr.display), " ")}"

		exit_code = new(program)
			.args(arguments)
			.exec_exit_code!()?

		if exit_code == 0 {
			Ok({})
		} else {
			Err(ExecFailed({ command, exit_code }))
		}
	}

	## Execute a Cmd (using the builder pattern).
	## Stdin, stdout, and stderr are inherited from the parent process.
	##
	## You should prefer using [exec!] instead, only use this if you want to use [env], [envs] or [clear_envs].
	## If you want to capture the output, use [exec_output!] instead.
	##
	## ```roc
	## Cmd.new("cargo")
	##     .arg(["build")
	##     .env("RUST_BACKTRACE", "1")
	##     .exec_cmd!()?
	## ```
	exec_cmd! : Cmd => Try({}, [ExecCmdFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_cmd! = |cmd| {
		command = to_str(cmd)
		exit_code = exec_exit_code!(cmd)?

		if exit_code == 0 {
			Ok({})
		} else {
			Err(ExecCmdFailed({ command, exit_code }))
		}
	}

	## Execute command and capture stdout and stderr as UTF-8 strings.
	## Invalid UTF-8 sequences are replaced with the Unicode replacement character.
	##
	## Use [exec_output_bytes!] instead if you want to capture the output in the original form as bytes.
	## [exec_output_bytes!] may also be used for maximum performance, because you may be able to avoid unnecessary UTF-8 conversions.
	##
	## ```roc
	## cmd_output =
	##     Cmd.new("echo")
	##         .args(["Hi"])
	##         .exec_output!()?
	##
	## Stdout.line!("Echo output: ${cmd_output.stdout_utf8}")?
	## ```
	exec_output! : Cmd => Try({ stdout_utf8 : Str, stderr_utf8_lossy : Str }, [StdoutContainsInvalidUtf8({ cmd_str : Str, err : [BadUtf8({ problem : _, index : U64 })] }), NonZeroExitCode({ command : Str, exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_output! = |cmd| {
		cmd_str = to_str(cmd)
		exec_try = Host.cmd_exec_output!(to_host_cmd(cmd))

		match exec_try {
			Ok({ stderr_bytes, stdout_bytes }) => {
				stdout_utf8 = Str.from_utf8(stdout_bytes)
					.map_err(|err| StdoutContainsInvalidUtf8({ cmd_str, err }))?

				stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

				Ok({ stdout_utf8, stderr_utf8_lossy })
			}

			Err(NonZeroExitCode({ exit_code, stderr_bytes, stdout_bytes })) => {
				stdout_utf8_lossy = Str.from_utf8_lossy(stdout_bytes)
				stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

				Err(NonZeroExitCode({ command: cmd_str, exit_code, stdout_utf8_lossy, stderr_utf8_lossy }))
			}

			Err(FailedToGetExitCode(err)) => Err(FailedToGetExitCode({ command: cmd_str, err }))
		}
	}

	## Execute command and capture stdout and stderr in the original form as bytes.
	##
	## Use [exec_output!] instead if you want to get the output as UTF-8 strings.
	##
	## ```roc
	## cmd_output =
	##     Cmd.new("echo")
	##         .args(["Hi"])
	##         .exec_output_bytes!()?
	##
	## Stdout.line!("${Str.inspect(cmd_output_bytes)}")? # {stderr_bytes: [], stdout_bytes: [72, 105, 10]}
	## ```
	exec_output_bytes! : Cmd => Try({ stderr_bytes : List(U8), stdout_bytes : List(U8) }, [NonZeroExitCodeB({ exit_code : I32, stdout_bytes : List(U8), stderr_bytes : List(U8) }), FailedToGetExitCodeB(IOErr), ..])
	exec_output_bytes! = |cmd| {
		exec_try = Host.cmd_exec_output!(to_host_cmd(cmd))

		match exec_try {
			Ok({ stderr_bytes, stdout_bytes }) =>
				Ok({ stdout_bytes, stderr_bytes })

			Err(NonZeroExitCode({ exit_code, stderr_bytes, stdout_bytes })) => {
				Err(NonZeroExitCodeB({ exit_code, stdout_bytes, stderr_bytes }))
			}

			Err(FailedToGetExitCode(err)) => {
				Err(FailedToGetExitCodeB(err))
			}
		}
	}

	## Execute a command and return its exit code.
	## Stdin, stdout, and stderr are inherited from the parent process.
	##
	## You should prefer using [exec!] or [exec_cmd!] instead, only use this if you want to take a specific action based on a **specific non-zero exit code**.
	## For example, `roc check` returns exit code 1 if there are errors, and exit code 2 if there are only warnings.
	## So, you could use `exec_exit_code!` to ignore warnings on `roc check`.
	##
	## ```roc
	## exit_code = Cmd.new("cat").arg("non_existent.txt").exec_exit_code!()?
	## ```
	exec_exit_code! : Cmd => Try(I32, [FailedToGetExitCode({ command : Str, err : IOErr }), ..])
	exec_exit_code! = |cmd| {
		command = to_str(cmd)

		match Host.cmd_exec_exit_code!(to_host_cmd(cmd)) {
			Ok(num) => Ok(num)
			Err(io_err) => Err(FailedToGetExitCode({ command, err: io_err }))
		}
	}

	## Create a new command with the given program name. Use a function that starts with `exec_` to execute it.
	##
	## ```roc
	## cmd = Cmd.new("ls")
	## ```
	new : OsStr -> Cmd
	new = |program| {
		args: [],
		clear_envs: Bool.False,
		envs: [],
		program,
	}

	## Create a new command from a Roc string.
	new_str : Str -> Cmd
	new_str = |program| new(OsStr.from_str(program))

	## Add a single argument to the command.
	## ❗ Shell features like variable substitution (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
	##
	## ```roc
	## cmd = Cmd.new("ls").arg("-l")
	## ```
	arg : Cmd, OsStr -> Cmd
	arg = |cmd, a| {
		..cmd,
		args: cmd.args.append(a),
	}

	## Add a single string argument to the command.
	arg_str : Cmd, Str -> Cmd
	arg_str = |cmd, a| arg(cmd, OsStr.from_str(a))

	## Add multiple arguments to the command.
	## ❗ Shell features like variable substitution (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
	##
	## ```roc
	## cmd = Cmd.new("ls").args(["-l", "-a"])
	## ```
	args : Cmd, List(OsStr) -> Cmd
	args = |cmd, new_args| {
		..cmd,
		args: cmd.args.concat(new_args),
	}

	## Add multiple string arguments to the command.
	args_str : Cmd, List(Str) -> Cmd
	args_str = |cmd, new_args| args(cmd, new_args.map(OsStr.from_str))

	## Add a single environment variable to the command.
	##
	##
	## ```roc
	## cmd = Cmd.new("env").env("FOO", "bar") # add the environment variable "FOO" with value "bar"
	## ```
	env : Cmd, OsStr, OsStr -> Cmd
	env = |cmd, key, value| {
		{ ..cmd, envs: cmd.envs.append((key, value)) }
	}

	## Add a single string environment variable to the command.
	env_str : Cmd, Str, Str -> Cmd
	env_str = |cmd, key, value| env(cmd, OsStr.from_str(key), OsStr.from_str(value))

	## Add multiple environment variables to the command.
	##
	## ```roc
	## cmd = Cmd.new("env").envs([("FOO", "bar"), ("BAZ", "qux")])
	## ```
	envs : Cmd, List((OsStr, OsStr)) -> Cmd
	envs = |cmd, pairs| { ..cmd, envs: cmd.envs.concat(pairs) }

	## Add multiple string environment variables to the command.
	envs_str : Cmd, List((Str, Str)) -> Cmd
	envs_str = |cmd, pairs| {
		arg_pairs = pairs.map(|(key, value)| (OsStr.from_str(key), OsStr.from_str(value)))
		envs(cmd, arg_pairs)
	}

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
	clear_envs : Cmd -> Cmd
	clear_envs = |cmd| { ..cmd, clear_envs: Bool.True }

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
			match Env.platform!().os {
				WINDOWS => Bool.True
				_ => Bool.False
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

	## Render a command configuration as a stable, escaped string.
	to_str : Cmd -> Str
	to_str = |cmd|
		"Cmd({ program: ${Str.inspect(cmd.program)}, args: ${Str.inspect(cmd.args)}, envs: ${Str.inspect(cmd.envs)}, clear_envs: ${Str.inspect(cmd.clear_envs)} })"

	## Customize command output for `Str.inspect`.
	to_inspect : Cmd -> Str
	to_inspect = |cmd| to_str(cmd)
}

flatten_arg_pairs : List((OsStr, OsStr)), List(OsStr), U64 -> List(OsStr)
flatten_arg_pairs = |pairs, acc, idx| {
	if idx >= pairs.len() {
		acc
	} else {
		match pairs.get(idx) {
			Ok(pair) =>
				flatten_arg_pairs(pairs, acc.append(pair.0).append(pair.1), idx + 1)
			Err(_) =>
				acc
			}
	}
}

to_host_cmd : Cmd -> Host.Cmd
to_host_cmd = |cmd| {
	args: cmd.args.map(OsStr.to_raw),
	clear_envs: cmd.clear_envs,
	envs: flatten_arg_pairs(cmd.envs, [], 0).map(OsStr.to_raw),
	program: OsStr.to_raw(cmd.program),
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
			split_on(bytes, if is_windows ';' else ':')
				.keep_if(|segment| !List.is_empty(segment))
				.map(Path.unix_bytes)

		WindowsU16s(u16s) =>
			split_on(u16s, if is_windows ';' else ':')
				.keep_if(|segment| !List.is_empty(segment))
				.map(Path.windows_u16s)
		}

## Split a list into segments on a separator element (segments may be empty).
split_on : List(a), a -> List(List(a)) where [a.is_eq : a, a -> Bool]
split_on = |items, sep| split_on_help(items, sep, [], [])

split_on_help : List(a), a, List(a), List(List(a)) -> List(List(a)) where [a.is_eq : a, a -> Bool]
split_on_help = |remaining, sep, current, acc|
	match remaining {
		[] => acc.append(current)
		[x, .. as rest] if x == sep => split_on_help(rest, sep, [], acc.append(current))
		[x, .. as rest] => split_on_help(rest, sep, current.append(x), acc)
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
		[] => Bool.False
		[dir, .. as rest] =>
			if search_extensions!(dir, command, extensions, is_windows) {
				Bool.True
			} else {
				search_dirs!(rest, command, extensions, is_windows)
			}
		}

search_extensions! : Path, Str, List(Str), Bool => Bool
search_extensions! = |dir, command, extensions, is_windows|
	match extensions {
		[] => Bool.False
		[ext, .. as rest] =>
			if candidate_available!(dir.join(command.concat(ext)), is_windows) {
				Bool.True
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
		Ok(Bool.True) => not_directory!(candidate)
		Ok(Bool.False) => Bool.False
		Err(_) => Bool.False
	}
}

## `is_dir!` does not follow symlinks, so a symlink to an executable is kept while
## a real directory is rejected. A symlink pointing at a directory is not caught.
not_directory! : Path => Bool
not_directory! = |candidate|
	match Path.is_dir!(candidate) {
		Ok(is_dir) => !is_dir
		Err(_) => Bool.True
	}

## Inspection is escaped and includes the full immutable command configuration.
expect {
	cmd = Cmd.new_str("echo\nnext")
		.arg_str("hello world")
		.env_str("NAME", "Roc")
		.clear_envs()

	Str.inspect(cmd) == "Cmd({ program: OsStr.utf8(\"echo\\nnext\"), args: [OsStr.utf8(\"hello world\")], envs: [(OsStr.utf8(\"NAME\"), OsStr.utf8(\"Roc\"))], clear_envs: True })"
}

## A name is a path only when it carries a separator for the current platform.
expect has_separator("git", Bool.False) == Bool.False
expect has_separator("./git", Bool.False) == Bool.True
expect has_separator("a\\b", Bool.False) == Bool.False
expect has_separator("a\\b", Bool.True) == Bool.True

## Splitting keeps every segment, including a trailing empty one after a separator.
expect split_on([1.U8, 2, 58, 3], 58) == [[1, 2], [3]]
expect split_on([59.U16, 1, 59], 59) == [[], [1], []]

## PATH splitting preserves raw bytes, including non-UTF-8 directory entries.
expect {
	# "/a" ++ ":" ++ "/<0xFF>b" — the 0xFF byte is not valid UTF-8.
	path = OsStr.unix_bytes([0x2F, 0x61, 0x3A, 0x2F, 0xFF, 0x62])
	path_dirs(path, Bool.False) == [Path.unix_bytes([0x2F, 0x61]), Path.unix_bytes([0x2F, 0xFF, 0x62])]
}

## The UTF-8 PATH representation splits the same way.
expect path_dirs(OsStr.utf8("/a:/b"), Bool.False) == [Path.utf8("/a"), Path.utf8("/b")]

## Empty PATH entries (a stray or trailing separator) are dropped, not resolved to root.
expect path_dirs(OsStr.utf8("/a::/b:"), Bool.False) == [Path.utf8("/a"), Path.utf8("/b")]

## Windows PATH splits on ';' and preserves UTF-16 units.
expect {
	path = OsStr.windows_u16s([0x43, 0x3B, 0x44])
	path_dirs(path, Bool.True) == [Path.windows_u16s([0x43]), Path.windows_u16s([0x44])]
}
