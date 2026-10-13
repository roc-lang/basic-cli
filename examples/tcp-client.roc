## Exchange lines with a local TCP echo server over a buffered connection.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.Duration
import pf.OsStr
import pf.Tcp
import pf.Stdout
import pf.Stdin

# To try it interactively, start an echo server in another terminal first:
#
#     $ ncat -e $(which cat) -l 8085
#
# then run this example.
main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# The wait to connect is separate from the timeout the connection holds
	# for each of its reads and writes. Windows takes about two seconds to
	# report a refused connection, so a shorter wait would time out first.
	conn = Tcp.connect!("127.0.0.1", 8085, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5) })?

	verify_connection_methods!(conn)?

	Stdout.line!("Connected!")?

	chat!(conn)?
	pipeline!(conn, ["one", "two", "three"])
}

## Exercise every read and write operation against the echo test server.
verify_connection_methods! : Tcp.Connection => Try({}, _)
verify_connection_methods! = |conn| {
	conn.write_bytes!([1, 2, 3])?
	exact_bytes = conn.read_exactly!(3)?
	expect exact_bytes == [1, 2, 3]

	conn.write_utf8!("until|")?
	until_bytes = conn.read_until!('|')?
	expect until_bytes == "until|".to_utf8()

	conn.write_bytes!(['*'])?
	up_to_bytes = conn.read_up_to!(1)?
	expect up_to_bytes == ['*']

	# Nothing more was sent, so a read with a short timeout expires. It
	# consumes nothing, and the connection stays usable.
	idle = conn.with_timeout(Duration.millis(50)).read_line!()
	expect idle == Err(TcpErr(TimedOut))

	Ok({})
}

## Read a line from stdin, send it to the server, print the response, repeat.
chat! : Tcp.Connection => Try({}, _)
chat! = |conn| {
	Stdout.write!("> ")?
	match Stdin.line!() {
		# No more input: move on.
		Err(EndOfInput) => Stdout.line!("")
		Err(BadUtf8(problem)) => Err(BadUtf8(problem))
		Err(StdinErr(err)) => Err(StdinErr(err))
		Ok(out_msg) => {
			conn.write_utf8!("${out_msg}\n")?
			in_msg = conn.read_line!()?
			Stdout.line!("< ${in_msg}")?
			chat!(conn)
		}
	}
}

## Send several requests at once, then read the replies as a stream of lines.
pipeline! : Tcp.Connection, List(Str) => Try({}, _)
pipeline! = |conn, requests| {
	conn.write_utf8!(Str.join_with(requests, "\n").concat("\n"))?

	var $pending = requests.len()
	for! item in conn.lines() {
		match item {
			Ok(line) => Stdout.line!("<< ${line}")?
			# These two concern one line; the stream carries on with the next.
			Err(BadUtf8({ index, .. })) => Stdout.line!("<< (invalid UTF-8 at byte ${index.to_str()})")?
			Err(ReadLimitExceeded(limit)) => Stdout.line!("<< (a line longer than ${limit.to_str()} bytes)")?
			# The connection failed or timed out, and this is the last item.
			Err(TcpErr(err)) => {
				return Err(TcpErr(err))
			}
		}
		# The echo server keeps the connection open, so stop at the last reply
		# instead of waiting for the end of input.
		$pending = $pending - 1
		if $pending == 0 {
			break
		}
	}

	Ok({})
}
