import Duration
import Host
import IOErr
import Resource

## The line limit a new connection holds: 1 MiB.
default_line_limit : U64
default_line_limit = 1_048_576

## The accept wait as the host takes it, in nanoseconds.
accept_wait : [NoTimeout, After(Duration)] -> [NoTimeout, After(U64)]
accept_wait = |accept_timeout|
	match accept_timeout {
		NoTimeout => NoTimeout
		After(duration) => After(duration.to_nanos())
	}

## Connect to TCP servers, accept TCP clients, and exchange bytes and lines.
##
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for additional runtime details.
##
## Every failure of the network or the operating system is `TcpErr(IOErr)`, so
## results compare with `==`: `result == Err(TcpErr(ConnectionRefused))`.
##
## Timeouts are [Duration]s. The wait to connect or to accept bounds that one
## call. The connection it produces holds its own I/O timeout, which bounds
## each later read or write as a whole. `Duration.zero` expires immediately,
## and an expired timeout is always `TcpErr(TimedOut)`.
##
## ```roc
## conn = Tcp.connect!("example.com", 80, { connect_timeout: Duration.seconds(5), io_timeout: Duration.seconds(5) })?
## conn.write_utf8!("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n")?
## status_line = conn.read_line!()?
## ```
##
## A server accepts connections from a [Listener]:
##
## ```roc
## listener = Tcp.listen!("127.0.0.1", 8085, Duration.seconds(5))?
## while True {
##     conn = listener.accept!({ accept_timeout: NoTimeout, io_timeout: Duration.seconds(30) })?
##     line = conn.read_line!()?
##     conn.write_utf8!("you said ${line}\n")?
## }
## ```
Tcp :: [].{

	# A tag union that crosses the host boundary is closed by design, so every
	# function below rebuilds the error it forwards from the host. That gives
	# callers an open union, which `?` can combine with other error types
	# however the function is called.

	## A listening socket.
	##
	## The socket is closed when the last reference to the listener is
	## released, or earlier by [close!]. Copies of a listener share one
	## socket, so closing one closes them all.
	Listener :: { host : Resource.TcpListener }.{

		## Render the listener without exposing its host handle.
		to_inspect : Listener -> Str
		to_inspect = |_| "Tcp.Listener(<opaque>)"

		## The port this listener is bound to. After `Tcp.listen!(host, 0, …)`
		## this is the port the operating system chose. `Closed` after [close!].
		local_port! : Listener => Try(U16, [Closed, TcpErr(IOErr)])
		local_port! = |listener|
			match Host.tcp_local_port!(listener.host) {
				Ok(port) => Ok(port)
				Err(Closed) => Err(Closed)
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Wait for a client to connect.
		##
		## `accept_timeout` bounds this call only: `NoTimeout` waits
		## indefinitely, and `After(duration)` gives up with
		## `Err(TcpErr(TimedOut))`, after which the listener can accept again.
		## `io_timeout` is the timeout the new [Connection] holds for its reads
		## and writes; a connection never inherits the accept wait.
		##
		## `Closed` after [close!].
		##
		## ```roc
		## match listener.accept!({ accept_timeout: After(Duration.seconds(1)), io_timeout: Duration.seconds(30) }) {
		##     Ok(conn) => serve!(conn)?
		##     Err(TcpErr(TimedOut)) => {}
		##     Err(Closed) => { return Ok({}) }
		##     Err(TcpErr(err)) => { return Err(TcpErr(err)) }
		## }
		## ```
		accept! : Listener, { accept_timeout : [NoTimeout, After(Duration)], io_timeout : Duration } => Try(Connection, [Closed, TcpErr(IOErr)])
		accept! = |listener, options|
			match Host.tcp_accept!(listener.host, accept_wait(options.accept_timeout)) {
				Ok(host) => Ok(Connection.{ host, timeout: options.io_timeout, line_limit: default_line_limit })
				Err(Closed) => Err(Closed)
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Stop listening and release the port. Closing again succeeds.
		## Connections already accepted stay open.
		close! : Listener => Try({}, [TcpErr(IOErr)])
		close! = |listener|
			Host.tcp_listener_close!(listener.host)
				.map_err(|TcpErr(err)| TcpErr(err))
	}

	## Bind an address and listen for connections. Port zero asks the operating
	## system for a free port, which [Listener.local_port!] reports. The
	## timeout covers hostname resolution.
	##
	## ```roc
	## listener = Tcp.listen!("127.0.0.1", 0, Duration.seconds(5))?
	## port = listener.local_port!()?
	## ```
	listen! : Str, U16, Duration => Try(Listener, [TcpErr(IOErr)])
	listen! = |host, port, timeout|
		match Host.tcp_listen!(host, port, timeout.to_nanos()) {
			Ok(handle) => Ok(Listener.{ host: handle })
			Err(TcpErr(err)) => Err(TcpErr(err))
		}

	## A buffered TCP connection, with the I/O timeout and line limit its
	## reads and writes use.
	##
	## The connection is closed when the last reference to it is released.
	## Copies of a connection share one socket and one buffer, so every read,
	## whether of lines, delimited bytes or binary data, continues where the
	## previous one stopped. [with_timeout] and [with_line_limit] change the
	## settings of the copy they return, not the socket.
	##
	## Every read ends the same way: once the peer has closed its side and all
	## data has been returned, the next read is `Err(EndOfInput)`. An empty
	## `Ok` is real data, such as an empty line.
	##
	## A read that times out consumes nothing. Bytes that had arrived stay
	## buffered for the next read, so a client may simply read again. A write
	## that times out may have sent any prefix of its bytes: drop the
	## connection unless the protocol can resynchronise.
	Connection :: { host : Resource.TcpConnection, timeout : Duration, line_limit : U64 }.{

		## Render the connection without exposing its host handle.
		to_inspect : Connection -> Str
		to_inspect = |_| "Tcp.Connection(<opaque>)"

		## The same connection with another I/O timeout. Each read or write
		## through the result is bounded as a whole by `timeout`.
		##
		## ```roc
		## # Poll: is a line already here?
		## match conn.with_timeout(Duration.millis(10)).read_line!() {
		##     Ok(line) => handle!(line)?
		##     Err(TcpErr(TimedOut)) => {}
		##     Err(err) => { return Err(err) }
		## }
		## ```
		with_timeout : Connection, Duration -> Connection
		with_timeout = |conn, timeout| Connection.{ host: conn.host, timeout, line_limit: conn.line_limit }

		## The same connection with another limit, in bytes, on one record read
		## by [read_until!], [read_line!] or [lines]. The delimiter or line
		## terminator counts towards the limit. The default is 1,048,576 (1 MiB).
		with_line_limit : Connection, U64 -> Connection
		with_line_limit = |conn, max_bytes| Connection.{ host: conn.host, timeout: conn.timeout, line_limit: max_bytes }

		## Read at most `max_bytes` bytes, returning as soon as any have
		## arrived. Short reads are valid. Asking for zero bytes returns
		## `Ok([])` without waiting; otherwise the result is never empty, and a
		## closed peer is `Err(EndOfInput)`.
		read_up_to! : Connection, U64 => Try(List(U8), [EndOfInput, TcpErr(IOErr)])
		read_up_to! = |conn, max_bytes|
			match Host.tcp_read_up_to!(conn.host, max_bytes, conn.timeout.to_nanos()) {
				Ok(bytes) => Ok(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Read exactly `count` bytes. Zero succeeds without waiting.
		##
		## If the peer closes before `count` bytes arrive the result is
		## `Err(UnexpectedEndOfInput)`. The bytes that did arrive are not
		## consumed: [read_up_to!] returns them.
		read_exactly! : Connection, U64 => Try(List(U8), [UnexpectedEndOfInput, TcpErr(IOErr)])
		read_exactly! = |conn, count|
			match Host.tcp_read_exactly!(conn.host, count, conn.timeout.to_nanos()) {
				Ok(bytes) => Ok(bytes)
				Err(UnexpectedEndOfInput) => Err(UnexpectedEndOfInput)
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Read bytes through and including the next `delimiter`.
		##
		## If the peer closes first, the bytes before the end are returned
		## without a delimiter, and the read after that is `Err(EndOfInput)`.
		## So the result is never empty, and its last byte shows whether the
		## delimiter arrived.
		##
		## A record longer than the connection's line limit is
		## `Err(ReadLimitExceeded(limit))`. The rest of that record, through
		## its delimiter, is then discarded before the next read returns, as
		## part of that read and within its timeout.
		##
		## ```roc
		## field = conn.read_until!('|')?
		## ```
		read_until! : Connection, U8 => Try(List(U8), [EndOfInput, ReadLimitExceeded(U64), TcpErr(IOErr)])
		read_until! = |conn, delimiter|
			match Host.tcp_read_until!(conn.host, delimiter, conn.line_limit, conn.timeout.to_nanos()) {
				Ok(bytes) => Ok(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(ReadLimitExceeded(limit)) => Err(ReadLimitExceeded(limit))
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Read a line of text.
		##
		## A line ends at `\n`. The terminator is not returned, and one `\r`
		## before it is removed. If the peer closes without a final `\n` the
		## last line is still returned; after that the result is
		## `Err(EndOfInput)`. An empty line is `Ok("")`.
		##
		## A line longer than the connection's line limit is
		## `Err(ReadLimitExceeded(limit))`, and a line that is not valid UTF-8
		## is `BadUtf8`. Either way that line is skipped and the next call
		## reads the line after it. For the bytes of a line, use
		## `conn.read_until!('\n')`.
		read_line! : Connection => Try(Str, [EndOfInput, ReadLimitExceeded(U64), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), TcpErr(IOErr)])
		read_line! = |conn|
			match Host.tcp_read_line!(conn.host, conn.line_limit, conn.timeout.to_nanos()) {
				Ok(bytes) => Str.from_utf8(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(ReadLimitExceeded(limit)) => Err(ReadLimitExceeded(limit))
				Err(TcpErr(err)) => Err(TcpErr(err))
			}

		## Write all of `bytes`. They are sent at once, not buffered.
		write_bytes! : Connection, List(U8) => Try({}, [TcpErr(IOErr)])
		write_bytes! = |conn, bytes|
			Host.tcp_write!(conn.host, bytes, conn.timeout.to_nanos())
				.map_err(|TcpErr(err)| TcpErr(err))

		## Write a string as UTF-8. It is sent at once, not buffered.
		write_utf8! : Connection, Str => Try({}, [TcpErr(IOErr)])
		write_utf8! = |conn, str|
			write_bytes!(conn, Str.to_utf8(str))

		## Lazily read this connection as non-empty chunks of at most 64 KiB,
		## each returned as soon as it arrives. Chunk boundaries do not
		## correspond to the peer's writes, records, or text encoding
		## boundaries. For a chosen size, call [read_up_to!] in a loop.
		##
		## Building the stream reads nothing; each item is one read with the
		## connection's timeout. The stream ends when the peer closes. A
		## `TcpErr` item, including `TcpErr(TimedOut)`, is the last one; the
		## connection stays usable and a new stream may be started.
		##
		## ```roc
		## for! item in conn.chunks() {
		##     bytes = item?
		##     $total = $total + bytes.len()
		## }
		## ```
		##
		## The stream holds no data of its own, so it can be mixed with the
		## other reads and with writes. It keeps the connection open until it
		## has finished or is released.
		chunks : Connection -> Stream(Try(List(U8), [TcpErr(IOErr)]))
		chunks = |conn|
			# Keep the connection in the state, not the callback capture, so
			# Finished can release it even when the terminal continuation is
			# retained.
			Stream.custom(
				Reading(conn),
				Unknown,
				|state|
					match state {
						Finished => Err(NoMore)
						Reading(current) =>
							match read_up_to!(current, 65_536) {
								Ok(bytes) => Ok((Ok(bytes), Reading(current)))
								Err(EndOfInput) => Err(NoMore)
								Err(TcpErr(err)) => Ok((Err(TcpErr(err)), Finished))
							}
					},
			)

		## Lazily read this connection a line at a time, as [read_line!] does.
		##
		## Building the stream reads nothing; each item is one read with the
		## connection's timeout and line limit. The stream ends when the peer
		## closes. `BadUtf8` and `ReadLimitExceeded` items concern one line, and
		## the stream continues with the next. A `TcpErr` item, including
		## `TcpErr(TimedOut)`, is the last one; the connection stays usable, so
		## a client that tolerates idle periods calls `conn.lines()` again.
		##
		## ```roc
		## for! item in conn.lines() {
		##     match item {
		##         Ok(line) => Stdout.line!(line)?
		##         Err(BadUtf8(_)) => {}
		##         Err(ReadLimitExceeded(_)) => {}
		##         Err(TcpErr(err)) => { return Err(TcpErr(err)) }
		##     }
		## }
		## ```
		##
		## The stream holds no data of its own, so it can be mixed with the
		## other reads and with writes, and leaving the loop early loses
		## nothing. It keeps the connection open until it has finished or is
		## released.
		lines : Connection -> Stream(Try(Str, [ReadLimitExceeded(U64), BadUtf8({ problem : Str.Utf8Problem, index : U64 }), TcpErr(IOErr)]))
		lines = |conn|
			# Keep the connection in the state, not the callback capture, so
			# Finished can release it even when the terminal continuation is
			# retained.
			Stream.custom(
				Reading(conn),
				Unknown,
				|state|
					match state {
						Finished => Err(NoMore)
						Reading(current) =>
							match read_line!(current) {
								Ok(text) => Ok((Ok(text), Reading(current)))
								Err(EndOfInput) => Err(NoMore)
								Err(BadUtf8(problem)) => Ok((Err(BadUtf8(problem)), Reading(current)))
								Err(ReadLimitExceeded(limit)) => Ok((Err(ReadLimitExceeded(limit)), Reading(current)))
								Err(TcpErr(err)) => Ok((Err(TcpErr(err)), Finished))
							}
					},
			)
	}

	## Open a TCP connection.
	##
	## `connect_timeout` bounds this call, across hostname resolution and every
	## address the name resolves to. `io_timeout` is the timeout the new
	## [Connection] holds for its reads and writes.
	##
	## A port nobody listens on is `Err(TcpErr(ConnectionRefused))` once the
	## operating system reports it. Windows retries for about two seconds
	## first, so a shorter `connect_timeout` gives `Err(TcpErr(TimedOut))` there.
	##
	## ```roc
	## conn = Tcp.connect!("localhost", 8080, { connect_timeout: Duration.seconds(1), io_timeout: Duration.seconds(5) })?
	## ```
	##
	## Valid hostnames look like `127.0.0.1`, `::1`, `localhost`, or `roc-lang.org`.
	connect! : Str, U16, { connect_timeout : Duration, io_timeout : Duration } => Try(Connection, [TcpErr(IOErr)])
	connect! = |host, port, options|
		match Host.tcp_connect!(host, port, options.connect_timeout.to_nanos()) {
			Ok(handle) => Ok(Connection.{ host: handle, timeout: options.io_timeout, line_limit: default_line_limit })
			Err(TcpErr(err)) => Err(TcpErr(err))
		}
}

expect default_line_limit == 1_048_576
expect accept_wait(NoTimeout) == NoTimeout
expect accept_wait(After(Duration.millis(250))) == After(250_000_000)
expect accept_wait(After(Duration.zero)) == After(0)
