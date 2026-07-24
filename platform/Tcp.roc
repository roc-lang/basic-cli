import Host

## Connect to TCP servers and exchange buffered byte streams.
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for additional runtime details.
##
## Timeout arguments are in milliseconds and apply to the whole operation,
## including every underlying read/write attempt. A zero timeout fails
## immediately. Read and write timeouts are returned as
## `TcpReadErr(TimedOut)` and `TcpWriteErr(TimedOut)` respectively.
Tcp :: [].{

	## Represents a TCP stream.
	##
	## The connection is automatically closed when the last reference to the
	## stream is dropped. It wraps an opaque host-side `BufReader<TcpStream>`
	## handle.
	Stream :: { host : Host.TcpStream }.{

		## Render the stream without exposing its host handle.
		to_inspect : Stream -> Str
		to_inspect = |_| "Tcp.Stream(<opaque>)"

		## Read up to a number of bytes, waiting at most `timeout_ms` milliseconds.
		read_up_to! : Stream, U64, U64 => Try(List(U8), _)
		read_up_to! = |stream, bytes_to_read, timeout_ms|
			Host.tcp_read_up_to!(stream.host, bytes_to_read, timeout_ms)
				.map_err(|err| TcpReadErr(parse_stream_err(err)))

		## Read an exact number of bytes, waiting at most `timeout_ms` milliseconds.
		##
		## `TcpUnexpectedEOF` is returned if the stream ends before the specified
		## number of bytes is reached.
		read_exactly! : Stream, U64, U64 => Try(List(U8), _)
		read_exactly! = |stream, bytes_to_read, timeout_ms|
			match Host.tcp_read_exactly!(stream.host, bytes_to_read, timeout_ms) {
				Ok(bytes) => Ok(bytes)
				Err("UnexpectedEof") => Err(TcpUnexpectedEOF)
				Err(err) => Err(TcpReadErr(parse_stream_err(err)))
			}

		## Read until a delimiter or EOF is reached, consuming at most `max_bytes`
		## and waiting at most `timeout_ms` milliseconds.
		## If found, the delimiter is included as the last byte. Returns
		## `TcpReadLimitExceeded(max_bytes)` if the delimiter was not found within
		## the limit.
		read_until! : Stream, U8, U64, U64 => Try(List(U8), _)
		read_until! = |stream, byte, max_bytes, timeout_ms|
			match Host.tcp_read_until!(stream.host, byte, max_bytes, timeout_ms) {
				Ok(bytes) => Ok(bytes)
				Err("LimitExceeded") => Err(TcpReadLimitExceeded(max_bytes))
				Err(err) => Err(TcpReadErr(parse_stream_err(err)))
			}

		## Read at most `max_bytes` through a newline (`\n`, byte 10) or EOF as
		## UTF-8, waiting at most `timeout_ms` milliseconds. If found, the newline
		## is included as the last character.
		read_line! : Stream, U64, U64 => Try(Str, _)
		read_line! = |stream, max_bytes, timeout_ms|
			match read_until!(stream, 10, max_bytes, timeout_ms) {
				Ok(bytes) => Str.from_utf8(bytes).map_err(|err| TcpReadBadUtf8(err))
				Err(err) => Err(err)
			}

		## Write bytes, waiting at most `timeout_ms` milliseconds.
		write! : Stream, List(U8), U64 => Try({}, _)
		write! = |stream, bytes, timeout_ms|
			Host.tcp_write!(stream.host, bytes, timeout_ms)
				.map_err(|err| TcpWriteErr(parse_stream_err(err)))

		## Write a string as UTF-8, waiting at most `timeout_ms` milliseconds.
		write_utf8! : Stream, Str, U64 => Try({}, _)
		write_utf8! = |stream, str, timeout_ms|
			write!(stream, Str.to_utf8(str), timeout_ms)
	}

	## Represents errors that can occur when connecting to a remote host.
	ConnectErr : [
		PermissionDenied,
		AddrInUse,
		AddrNotAvailable,
		ConnectionRefused,
		Interrupted,
		TimedOut,
		Unsupported,
		Unrecognized(Str),
	]

	## Represents errors that can occur when performing an effect with a `Stream`.
	StreamErr : [
		StreamNotFound,
		PermissionDenied,
		ConnectionRefused,
		ConnectionReset,
		Interrupted,
		TimedOut,
		OutOfMemory,
		BrokenPipe,
		Unrecognized(Str),
	]

	## Opens a TCP connection, waiting at most `timeout_ms` milliseconds across
	## DNS resolution and all resolved addresses. A zero timeout fails immediately.
	##
	## ```roc
	## # Connect to localhost:8080
	## stream = Tcp.connect!("localhost", 8080, 5_000)?
	## ```
	##
	## Valid hostnames look like `127.0.0.1`, `::1`, `localhost`, or `roc-lang.org`.
	connect! = |host, port, timeout_ms|
		Host.tcp_connect!(host, port, timeout_ms)
			.map_ok(|stream| Stream.{ host: stream })
			.map_err(parse_connect_err)

	## Convert a `ConnectErr` to a `Str` you can print.
	connect_err_to_str = |err|
		match err {
			PermissionDenied => "PermissionDenied"
			AddrInUse => "AddrInUse"
			AddrNotAvailable => "AddrNotAvailable"
			ConnectionRefused => "ConnectionRefused"
			Interrupted => "Interrupted"
			TimedOut => "TimedOut"
			Unsupported => "Unsupported"
			Unrecognized(message) => "Unrecognized Error: ${message}"
		}

	## Convert a `StreamErr` to a `Str` you can print.
	stream_err_to_str = |err|
		match err {
			StreamNotFound => "StreamNotFound"
			PermissionDenied => "PermissionDenied"
			ConnectionRefused => "ConnectionRefused"
			ConnectionReset => "ConnectionReset"
			Interrupted => "Interrupted"
			TimedOut => "TimedOut"
			OutOfMemory => "OutOfMemory"
			BrokenPipe => "BrokenPipe"
			Unrecognized(message) => "Unrecognized Error: ${message}"
		}
}

# ---- internal helpers (module-private) -----------------------------------------

parse_connect_err = |err|
	match err {
		"ErrorKind::PermissionDenied" => PermissionDenied
		"ErrorKind::AddrInUse" => AddrInUse
		"ErrorKind::AddrNotAvailable" => AddrNotAvailable
		"ErrorKind::ConnectionRefused" => ConnectionRefused
		"ErrorKind::Interrupted" => Interrupted
		"ErrorKind::TimedOut" => TimedOut
		"ErrorKind::Unsupported" => Unsupported
		other => Unrecognized(other)
	}

parse_stream_err = |err|
	match err {
		"StreamNotFound" => StreamNotFound
		"ErrorKind::PermissionDenied" => PermissionDenied
		"ErrorKind::ConnectionRefused" => ConnectionRefused
		"ErrorKind::ConnectionReset" => ConnectionReset
		"ErrorKind::Interrupted" => Interrupted
		"ErrorKind::TimedOut" => TimedOut
		"ErrorKind::OutOfMemory" => OutOfMemory
		"ErrorKind::BrokenPipe" => BrokenPipe
		other => Unrecognized(other)
	}

expect parse_connect_err("ErrorKind::TimedOut") == TimedOut

expect parse_stream_err("ErrorKind::TimedOut") == TimedOut
