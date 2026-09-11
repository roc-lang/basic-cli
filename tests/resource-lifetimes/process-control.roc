## Spawn a copy of this executable and exchange byte-preserving pipe data.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Cmd
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
			.arg_str("--echo-helper")
			.cwd(directory)
			.timeout_ms(5000)
			.manage_tree(Bool.True)

		# run! captures bytes and represents the exit status explicitly.
		output = command.stdin(Bytes([0, 42, 255]))
			.run!() ? |err| RunFailed(err)
		if output.status != Exited(0) or output.stdout_bytes != [0, 42, 255] {
			Err(UnexpectedCapture)
		} else {
			child = command.stdin(Pipe).stdout(Pipe).stderr(Capture).spawn!() ? |err| SpawnFailed(err)
			_pid = child.pid!() ? |err| PidFailed(err)
			child.write!([0, 42, 255], 1000) ? |err| WriteFailed(err)
			child.close_stdin!() ? |err| CloseStdinFailed(err)
			bytes = read_all!(child, [])?
			result = child.wait!() ? |err| WaitFailed(err)
			child.close!() ? |err| CloseFailed(err)
			child.close!() ? |err| CloseFailed(err)
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
	match child.read!(2, 1000) ? |err| ReadFailed(err) {
		Stdout(chunk) => read_all!(child, bytes.concat(chunk))
		Stderr(_) => Err(UnexpectedStderr)
		End => Ok(bytes)
	}
}
