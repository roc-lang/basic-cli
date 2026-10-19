## Exercise automatic native-resource cleanup across aliases, lists, and early returns.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Duration
import pf.Env
import pf.File
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Tcp

timeout : Duration
timeout = Duration.seconds(5)

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	Env.with_temp_dir!(
		|workspace| {
			path = Path.join(workspace, "lines.txt")
			Path.write_utf8!(path, "first\nsecond\n")?
			for early in [False, True] {
				match read_aliases!(path, early) {
					Ok(_) => {}
					Err(ExpectedEarlyReturn) => {}
					Err(err) => return Err(err)
				}
			}
			Path.delete!(path)
		},
	)?

	for early in [False, True] {
		port = match release_listener!(early) {
			Ok(released_port) => released_port
			Err(Released(released_port)) => released_port
			Err(err) => return Err(err)
		}
		# Binding the same exclusive port proves the last Roc reference closed it.
		rebound = Tcp.listen!("127.0.0.1", port, timeout)?
		Tcp.Listener.close!(rebound)?
		Tcp.Listener.close!(rebound)?
	}

	listener = Tcp.listen!("127.0.0.1", 0, timeout)?
	server = connect_aliases!(listener)?
	# A live leaked client would time out here. Final ARC release must close it.
	match Tcp.Connection.read_up_to!(server, 1) {
		Err(EndOfInput) => {}
		Ok(bytes) => {
			return Err(ExpectedEndOfInput(bytes))
		}
		Err(TcpErr(err)) => {
			return Err(TcpErr(err))
		}
		Err(Interrupted) => {
			return Err(Interrupted)
		}
	}
	Tcp.Listener.close!(listener)?
	Stdout.line!("Resource aliases and early returns cleaned up")
}

read_aliases! = |path, early| {
	reader = File.open_reader!(path)?
	aliases = [reader, reader]
	if early {
		return Err(ExpectedEarlyReturn)
	}
	var $lines = []
	for alias in aliases {
		$lines = List.append($lines, File.Reader.read_until!(alias, '\n')?)
	}
	expect $lines == [Str.to_utf8("first\n"), Str.to_utf8("second\n")]
	Ok({})
}

release_listener! = |early| {
	listener = Tcp.listen!("127.0.0.1", 0, timeout)?
	aliases = [listener, listener]
	port = Tcp.Listener.local_port!(listener)?
	if early {
		return Err(Released(port))
	}
	for alias in aliases {
		alias_port = Tcp.Listener.local_port!(alias)?
		expect alias_port == port
	}
	Ok(port)
}

connect_aliases! = |listener| {
	port = Tcp.Listener.local_port!(listener)?
	client = Tcp.connect!("127.0.0.1", port, { connect_timeout: timeout, io_timeout: timeout })?
	aliases = [client, client]
	server = Tcp.Listener.accept!(listener, { accept_timeout: After(timeout), io_timeout: timeout })?
	for alias in aliases {
		Tcp.Connection.write_utf8!(alias, "x")?
	}
	bytes = Tcp.Connection.read_exactly!(server, 2)?
	expect bytes == Str.to_utf8("xx")
	Ok(server)
}
