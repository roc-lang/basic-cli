## Exchange lines with a local TCP echo server using buffered stream operations.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.1/HjwuwWAr7T9hqQXcb8VbxLJw1SzVhWQz5vvx4mnG3wDW.tar.zst" }

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

	stream : Tcp.Stream
	stream = Tcp.connect!("127.0.0.1", 8085, 1_000) ? |err| ConnectFailed(err)

	verify_stream_methods!(stream)?

	Stdout.line!("Connected!")?

	run!(stream)
}

## Exercise every read and write operation against the echo test server.
verify_stream_methods! : Tcp.Stream => Try({}, _)
verify_stream_methods! = |stream| {
	stream.write!([1, 2, 3], 1_000)?
	exact_bytes = stream.read_exactly!(3, 1_000)?
	expect exact_bytes == [1, 2, 3]

	stream.write_utf8!("until|", 1_000)?
	until_bytes = stream.read_until!(124, 64, 1_000)?
	expect until_bytes == [117, 110, 116, 105, 108, 124]

	stream.write!([42], 1_000)?
	up_to_bytes = stream.read_up_to!(1, 1_000)?
	expect up_to_bytes == [42]

	Ok({})
}

## Read a line from stdin, send it to the server, print the response, repeat.
run! : Tcp.Stream => Try({}, _)
run! = |stream| {
	Stdout.write!("> ")?
	match Stdin.line!() {
		# No more input — exit cleanly.
		Err(EndOfFile) => Ok({})
		Err(StdinErr(err)) => Err(StdinReadFailed(err))
		Ok(out_msg) => {
			stream.write_utf8!("${out_msg}\n", 5_000) ? |err| TcpWriteFailed(err)
			in_msg = stream.read_line!(1_048_576, 5_000) ? |err| TcpReadFailed(err)
			Stdout.line!("< ${in_msg}")?
			run!(stream)
		}
	}
}
