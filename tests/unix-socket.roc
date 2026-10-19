## Native pathname stream sockets, including their resource and cleanup rules.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Duration
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.UnixSocket

long : Duration
long = Duration.seconds(5)

check : Bool, Str -> Try({}, [CheckFailed(Str)])
check = |condition, message| if condition Ok({}) else Err(CheckFailed(message))

main! : List(OsStr) => Try({}, _)
main! = |_| {
	path : Path.Path
	path = "s"
	listener = UnixSocket.listen!(path)?
	match UnixSocket.listen!(path) {
		Err(UnixSocketErr(_)) => {}
		_ => {
			return Err(CheckFailed("existing pathname was overwritten"))
		}
	}
	check(listener.accept!({ accept_timeout: After(Duration.zero), io_timeout: long }).map_ok(|_| {}) == Err(UnixSocketErr(TimedOut)), "zero accept timeout")?
	server = exchange!(listener, path)?
	var $lines = []
	for! item in server.lines() {
		$lines = $lines.append(item?)
	}
	check($lines == ["tail", "", "end"], "stream cursor and normal end")?
	check(server.read_up_to!(1) == Err(EndOfInput), "single reads report end")?
	listener.close!()?
	listener.close!()?
	check(listener.accept!({ accept_timeout: NoTimeout, io_timeout: long }).map_ok(|_| {}) == Err(Closed), "closed listener")?
	match UnixSocket.listen!(path) {
		Err(UnixSocketErr(_)) => {}
		_ => {
			return Err(CheckFailed("closing unexpectedly removed pathname"))
		}
	}
	path.delete!()?
	rebound = UnixSocket.listen!(path)?
	rebound.close!()?
	path.delete!()?
	Stdout.line!("UnixSocket buffering, streams and explicit pathname cleanup: ok")
}

exchange! : UnixSocket.Listener, Path.Path => Try(UnixSocket.Connection, _)
exchange! = |listener, path| {
	connect! = UnixSocket.connect!
	accept! = UnixSocket.Listener.accept!
	write! = UnixSocket.Connection.write_utf8!
	read! = UnixSocket.Connection.read_line!
	client = connect!(path, { connect_timeout: long, io_timeout: long })?
	server = accept!(listener, { accept_timeout: NoTimeout, io_timeout: long })?
	write!(client, "hello\r\n")?
	check(read!(server)? == "hello", "UTF-8 line framing")?
	client.write_bytes!([0, 255, 128])?
	check(server.read_exactly!(3)? == [0, 255, 128], "binary bytes")?
	client.write_utf8!("par")?
	check(server.with_timeout(Duration.millis(20)).read_line!() == Err(UnixSocketErr(TimedOut)), "partial line timeout")?
	client.write_utf8!("tial\nfield|next|")?
	check(server.read_line!()? == "partial", "timeout preserved the prefix")?
	copy = server
	check(copy.read_until!('|')? == Str.to_utf8("field|"), "copies share the cursor")?
	check(server.read_until!('|')? == Str.to_utf8("next|"), "delimited bytes")?
	server.write_utf8!("reply\n")?
	check(client.read_line!()? == "reply", "bidirectional writes")?
	client.write_utf8!("tail\n\nend\n")?
	Ok(server)
}
