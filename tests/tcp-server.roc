## Run a TCP server and its client in one process and print what each call
## returns, so that scripts/test.py can check the timeout, limit, end-of-input
## and stream rules of `Tcp.Listener` and `Tcp.Connection`.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Duration
import pf.Monotonic
import pf.OsStr
import pf.Stdout
import pf.Tcp

long : Duration
long = Duration.seconds(10)

short : Duration
short = Duration.millis(100)

main! : List(OsStr) => Try({}, _)
main! = |args| {
	# A second error beside the platform's, so each `?` below must widen.
	if args.len() > 0 {
		return Err(UnexpectedArguments)
	}

	listener = Tcp.listen!("127.0.0.1", 0, long)?
	port = listener.local_port!()?
	Stdout.line!("listening: ${Str.inspect(listener)}, port chosen: ${Str.inspect(port != 0)}")?
	Stdout.line!("second listen: ${show_unit(Tcp.listen!("127.0.0.1", port, long))}")?
	Stdout.line!("zero listen timeout: ${show_unit(Tcp.listen!("127.0.0.1", 0, Duration.zero))}")?

	accept_waits!(listener)?

	server = conversation!(listener, port)?

	# The client is gone. What it sent last is still delivered, and a new
	# stream picks up where the timed-out one stopped.
	for! item in server.lines() {
		Stdout.line!("restarted lines: ${show_line_item(item)}")?
	}
	Stdout.line!("restarted lines: ended")?
	Stdout.line!("read_line after the end: ${Str.inspect(server.read_line!())}")?
	Stdout.line!("read_until after the end: ${Str.inspect(server.read_until!('|'))}")?
	Stdout.line!("read_up_to after the end: ${Str.inspect(server.read_up_to!(1))}")?
	Stdout.line!("read_exactly after the end: ${Str.inspect(server.read_exactly!(1))}")?
	Stdout.line!("read_up_to zero after the end: ${Str.inspect(server.read_up_to!(0))}")?
	for! item in server.chunks() {
		Stdout.line!("chunks after the end: ${Str.inspect(item)}")?
	}
	Stdout.line!("chunks after the end: ended")?

	held_timeout!(listener, port)?
	function_values!(listener, port)?

	listener.close!()?
	listener.close!()?
	Stdout.line!("local_port after close: ${Str.inspect(listener.local_port!())}")?
	Stdout.line!("accept after close: ${show_unit(listener.accept!({ accept_timeout: NoTimeout, io_timeout: long }))}")?

	refused = Tcp.connect!("127.0.0.1", port, { connect_timeout: long, io_timeout: long }).map_ok(|_| {})
	Stdout.line!("connect after close is refused: ${Str.inspect(refused == Err(TcpErr(ConnectionRefused)))}")?
	zero = Tcp.connect!("127.0.0.1", port, { connect_timeout: Duration.zero, io_timeout: long }).map_ok(|_| {})
	Stdout.line!("zero connect timeout: ${Str.inspect(zero)}")?

	Stdout.line!("tcp server: ok")
}

## Render a result without its `Ok` value, which has no `==` of its own.
show_unit = |result| Str.inspect(result.map_ok(|_| {}))

## Render one item of `lines`, naming every tag an item can have.
show_line_item : Try(Str, [Interrupted, ReadLimitExceeded(U64), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), TcpErr(_)]) -> Str
show_line_item = |item|
	match item {
		Ok(line) => "line ${Str.inspect(line)}"
		Err(Interrupted) => "Interrupted"
		Err(BadUtf8({ index, .. })) => "bad utf8 at byte ${index.to_str()}"
		Err(ReadLimitExceeded(limit)) => "longer than ${limit.to_str()} bytes"
		Err(TcpErr(err)) => "TcpErr(${Str.inspect(err)})"
	}

## A bounded accept gives up with `TcpErr(TimedOut)` and leaves the listener
## usable; an unbounded one returns the client that is already waiting.
accept_waits! : Tcp.Listener => Try({}, _)
accept_waits! = |listener| {
	start = Monotonic.now!()
	bounded = listener.accept!({ accept_timeout: After(short), io_timeout: long }).map_ok(|_| {})
	waited = start.elapsed!()
	Stdout.line!("bounded accept: ${Str.inspect(bounded)}, equal to TimedOut: ${Str.inspect(bounded == Err(TcpErr(TimedOut)))}")?
	Stdout.line!("bounded accept waited: ${Str.inspect(waited >= short and waited < long)}")?
	Stdout.line!("zero accept: ${show_unit(listener.accept!({ accept_timeout: After(Duration.zero), io_timeout: long }))}")
}

## Everything that needs both ends alive. Returns the server's end; the
## client's is released on return, which closes it.
conversation! : Tcp.Listener, U16 => Try(Tcp.Connection, _)
conversation! = |listener, port| {
	client = Tcp.connect!("127.0.0.1", port, { connect_timeout: long, io_timeout: long })?
	server = listener.accept!({ accept_timeout: NoTimeout, io_timeout: long })?
	Stdout.line!("connected: ${Str.inspect(client)}")?

	# A zero timeout expires at once and consumes nothing: the same line is
	# then read in full.
	client.write_utf8!("hello\r\n")?
	Stdout.line!("first read: ${Str.inspect(server.read_line!())}")?
	client.write_utf8!("again\n")?
	polled = server.with_timeout(Duration.zero).read_line!()
	Stdout.line!("zero timeout: ${Str.inspect(polled)}, equal to TimedOut: ${Str.inspect(polled == Err(TcpErr(TimedOut)))}")?
	Stdout.line!("same data: ${Str.inspect(server.read_line!())}")?

	# A deadline that passes in the middle of a line loses none of it.
	client.write_utf8!("par")?
	Stdout.line!("partial line: ${Str.inspect(server.with_timeout(short).read_line!())}")?
	Stdout.line!("partial exact: ${Str.inspect(server.with_timeout(short).read_exactly!(8))}")?
	client.write_utf8!("tial\n")?
	Stdout.line!("whole line: ${Str.inspect(server.read_line!())}")?

	# An over-long record is skipped, and the next one is read.
	limited = server.with_line_limit(8)
	client.write_utf8!("this line is too long\nshort\n1234567\n12345678\nfield|next|")?
	Stdout.line!("over the limit: ${Str.inspect(limited.read_line!())}")?
	Stdout.line!("after it: ${Str.inspect(limited.read_line!())}")?
	Stdout.line!("at the limit: ${Str.inspect(limited.read_line!())}")?
	Stdout.line!("one over: ${Str.inspect(limited.read_line!())}")?
	Stdout.line!("delimited: ${Str.inspect(limited.read_until!('|').map_ok(Str.from_utf8_lossy))}")?
	Stdout.line!("delimited over: ${Str.inspect(limited.with_line_limit(3).read_until!('|'))}")?

	# Binary reads, the other way round.
	server.write_bytes!([0, 255, 128, 10])?
	Stdout.line!("exact: ${Str.inspect(client.read_exactly!(3))}")?
	Stdout.line!("up to: ${Str.inspect(client.read_up_to!(16))}")?
	Stdout.line!("none requested: ${Str.inspect(client.read_up_to!(0))}, ${Str.inspect(client.read_exactly!(0))}")?

	# Chunks are non-empty, at most 64 KiB, and end with the timeout.
	server.write_bytes!(List.repeat('x', 150_000))?
	var $total = 0
	var $sizes_ok = True
	var $last = "none"
	for! item in client.with_timeout(short).chunks() {
		match item {
			Ok(bytes) => {
				$total = $total + bytes.len()
				$sizes_ok = $sizes_ok and !bytes.is_empty() and bytes.len() <= 65_536
			}
			Err(TcpErr(err)) => {
				$last = Str.inspect(err)
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
		}
	}
	Stdout.line!("chunks: ${$total.to_str()} bytes, sizes ok: ${Str.inspect($sizes_ok)}, last item: TcpErr(${$last})")?

	# `BadUtf8` and `ReadLimitExceeded` concern one line and the stream goes
	# on. A timeout is the last item, and leaves the connection usable.
	client.write_utf8!("a\n")?
	client.write_bytes!([255, '\n'])?
	client.write_utf8!("much too long a line\n\nb\nunfin")?
	for! item in limited.with_timeout(short).lines() {
		Stdout.line!("lines: ${show_line_item(item)}")?
	}
	Stdout.line!("lines: ended")?

	client.write_utf8!("ished\nlast")?
	Ok(server)
}

## An accepted connection holds `io_timeout`, never the accept wait.
held_timeout! : Tcp.Listener, U16 => Try({}, _)
held_timeout! = |listener, port| {
	client = Tcp.connect!("127.0.0.1", port, { connect_timeout: long, io_timeout: Duration.zero })?
	server = listener.accept!({ accept_timeout: After(long), io_timeout: short })?

	start = Monotonic.now!()
	idle = server.read_line!()
	waited = start.elapsed!()
	Stdout.line!("accepted io timeout: ${Str.inspect(idle)}, waited: ${Str.inspect(waited >= short and waited < long)}")?

	# The connecting side holds its own, here one that has always expired.
	Stdout.line!("zero io timeout write: ${Str.inspect(client.write_utf8!("lost"))}")?
	Stdout.line!("zero io timeout read: ${Str.inspect(client.read_up_to!(1))}")?
	client.with_timeout(long).write_utf8!("kept\n")?
	Stdout.line!("after with_timeout: ${Str.inspect(server.read_line!())}")
}

## Every public function as a function value beside another error, so its
## error row has to be open. Rows are closed at the host boundary by design
## and rebuilt by each wrapper.
function_values! : Tcp.Listener, U16 => Try({}, _)
function_values! = |listener, port| {
	connect! = Tcp.connect!
	listen! = Tcp.listen!
	local_port! = Tcp.Listener.local_port!
	accept! = Tcp.Listener.accept!
	close! = Tcp.Listener.close!
	write_bytes! = Tcp.Connection.write_bytes!
	write_utf8! = Tcp.Connection.write_utf8!
	read_up_to! = Tcp.Connection.read_up_to!
	read_exactly! = Tcp.Connection.read_exactly!
	read_until! = Tcp.Connection.read_until!
	read_line! = Tcp.Connection.read_line!

	other = listen!("127.0.0.1", 0, long)?
	if local_port!(other)? == port {
		return Err(SamePortTwice)
	}
	close!(other)?

	client = connect!("127.0.0.1", port, { connect_timeout: long, io_timeout: long })?
	server = accept!(listener, { accept_timeout: NoTimeout, io_timeout: long })?
	write_bytes!(client, "ab|cd|".to_utf8())?
	write_utf8!(client, "line\nrest")?
	a = read_up_to!(server, 1)?
	b = read_exactly!(server, 2)?
	c = read_until!(server, '|')?
	line = read_line!(server)?
	Stdout.line!("function values: ${Str.inspect((Str.from_utf8_lossy(a), Str.from_utf8_lossy(b), Str.from_utf8_lossy(c), line))}")?

	with_timeout = Tcp.Connection.with_timeout
	with_line_limit = Tcp.Connection.with_line_limit
	lines = Tcp.Connection.lines
	chunks = Tcp.Connection.chunks

	# "rest" has no terminator yet, so `lines` times out without consuming it
	# and `chunks` then returns it.
	quick = with_line_limit(with_timeout(server, short), 16)
	var $items = []
	for! item in lines(quick) {
		$items = $items.append(show_line_item(item))
	}
	for! item in chunks(quick) {
		match item {
			Ok(bytes) => {
				$items = $items.append("chunk ${Str.inspect(Str.from_utf8_lossy(bytes))}")
			}
			Err(TcpErr(err)) => {
				$items = $items.append("TcpErr(${Str.inspect(err)})")
			}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
		}
	}
	write_utf8!(client, "end\n")?
	$items = $items.append("line ${Str.inspect(read_line!(server)?)}")
	Stdout.line!("stream function values: ${Str.join_with($items, ", ")}")
}
