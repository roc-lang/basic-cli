## Spawn a copy of this executable and exchange byte-preserving pipe data.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Cmd
import pf.Duration
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdin
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	if args.map(OsStr.display) == ["--echo-helper"] {
		bytes = Stdin.read_to_end!()?
		Stdout.write_bytes!(bytes)?
		Ok({})
	} else {
		executable = Env.exe_path!()?
		directory = Env.cwd!()?
		command = Cmd.new(Path.to_os_str(executable))
			.arg("--echo-helper")
			.cwd(directory)
			.timeout(Duration.seconds(5))
			.manage_tree(True)

		# run! captures bytes and represents the exit status explicitly.
		output = command.stdin(Bytes([0, 42, 255])).run!()?
		if output.status != Exited(0) or output.stdout_bytes != [0, 42, 255] {
			Err(UnexpectedCapture)
		} else {
			child = command.stdin(Pipe).stdout(Pipe).stderr(Capture).spawn!()?
			_pid = child.pid()
			child.write_bytes!([0, 42, 255], Duration.seconds(1))?
			child.close_stdin!()?
			bytes = read_all!(child, [])?
			result = child.wait!()?
			child.close!()?
			child.close!()?
			# The reused command and caller retain their native working-directory path.
			current = Env.cwd!()?
			if bytes == [0, 42, 255] and result.status == Exited(0) and Path.display(directory) == Path.display(current) {
				Stdout.line!("process control passed")?
				Ok({})
			} else {
				Err(UnexpectedPipeOutput)
			}
		}
	}
}

read_all! : Cmd.Child, List(U8) => Try(List(U8), _)
read_all! = |child, bytes| {
	match child.read!(Duration.seconds(1)) {
		Ok(Stdout(chunk)) => read_all!(child, bytes.concat(chunk))
		Ok(Stderr(_)) => Err(UnexpectedStderr)
		Err(EndOfInput) => Ok(bytes)
		Err(Closed) => Err(UnexpectedClosed)
		Err(CmdErr(err)) => Err(CmdErr(err))
		Err(Interrupted) => Err(Interrupted)
	}
}
