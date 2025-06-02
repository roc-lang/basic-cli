module [
    Stream,
    ConnectErr,
    StreamErr,
    connect!,
    read_up_to!,
    read_exactly!,
    read_until!,
    read_line!,
    write!,
    write_utf8!,
    connect_err_to_str,
    stream_err_to_str,
]

import Host

unexpected_eof_error_message = "UnexpectedEof"

## Represents a TCP stream.
Stream := Host.TcpStream

## Represents errors that can occur when connecting to a remote host.
ConnectErr a : [
    PermissionDenied,
    AddrInUse,
    AddrNotAvailable,
    ConnectionRefused,
    Interrupted,
    TimedOut,
    Unsupported,
    Unrecognized Str,
]a

parse_connect_err : Str -> ConnectErr _
parse_connect_err = |err|
    when err is
        "ErrorKind::PermissionDenied" -> PermissionDenied
        "ErrorKind::AddrInUse" -> AddrInUse
        "ErrorKind::AddrNotAvailable" -> AddrNotAvailable
        "ErrorKind::ConnectionRefused" -> ConnectionRefused
        "ErrorKind::Interrupted" -> Interrupted
        "ErrorKind::TimedOut" -> TimedOut
        "ErrorKind::Unsupported" -> Unsupported
        other -> Unrecognized(other)

## Represents errors that can occur when performing an effect with a [Stream].
StreamErr : [
    StreamNotFound,
    PermissionDenied,
    ConnectionRefused,
    ConnectionReset,
    Interrupted,
    OutOfMemory,
    BrokenPipe,
    Unrecognized Str,
]

parse_stream_err : Str -> StreamErr
parse_stream_err = |err|
    when err is
        "StreamNotFound" -> StreamNotFound
        "ErrorKind::PermissionDenied" -> PermissionDenied
        "ErrorKind::ConnectionRefused" -> ConnectionRefused
        "ErrorKind::ConnectionReset" -> ConnectionReset
        "ErrorKind::Interrupted" -> Interrupted
        "ErrorKind::OutOfMemory" -> OutOfMemory
        "ErrorKind::BrokenPipe" -> BrokenPipe
        other -> Unrecognized(other)

## Opens a TCP connection to a remote host.
##
## ```
## # Connect to localhost:8080
## stream = Tcp.connect!("localhost", 8080)?
## ```
##
## The connection is automatically closed when the last reference to the stream is dropped.
## Examples of
## valid hostnames:
##  - `127.0.0.1`
##  - `::1`
##  - `localhost`
##  - `roc-lang.org`
##
connect! : Str, U16 => Result Stream (ConnectErr _)
connect! = |host, port|
    Host.tcp_connect!(host, port)
    |> Result.map_ok(@Stream)
    |> Result.map_err(parse_connect_err)

## Read up to a number of bytes from the TCP stream.
##
## ```
## # Read up to 64 bytes from the stream
## received_bytes = Tcp.read_up_to!(stream, 64)?
## ```
##
## > To read an exact number of bytes or fail, you can use [Tcp.read_exactly!] instead.
read_up_to! : Stream, U64 => Result (List U8) [TcpReadErr StreamErr]
read_up_to! = |@Stream(stream), bytes_to_read|
    Host.tcp_read_up_to!(stream, bytes_to_read)
    |> Result.map_err(|err| TcpReadErr(parse_stream_err(err)))

## Read an exact number of bytes or fail.
##
## ```
## bytes = Tcp.read_exactly!(stream, 64)?
## ```
##
## `TcpUnexpectedEOF` is returned if the stream ends before the specfied number of bytes is reached.
##
read_exactly! : Stream, U64 => Result (List U8) [TcpReadErr StreamErr, TcpUnexpectedEOF]
read_exactly! = |@Stream(stream), bytes_to_read|
    Host.tcp_read_exactly!(stream, bytes_to_read)
    |> Result.map_err(
        |err|
            if err == unexpected_eof_error_message then
                TcpUnexpectedEOF
            else
                TcpReadErr(parse_stream_err(err)),
    )

## Read until a delimiter or EOF is reached.
##
## ```
## # Read until null terminator
## bytes = Tcp.read_until!(stream, 0)?
## ```
##
## If found, the delimiter is included as the last byte.
##
## > To read until a newline is found, you can use [Tcp.read_line!] which
## conveniently decodes to a [Str].
read_until! : Stream, U8 => Result (List U8) [TcpReadErr StreamErr]
read_until! = |@Stream(stream), byte|
    Host.tcp_read_until!(stream, byte)
    |> Result.map_err(|err| TcpReadErr(parse_stream_err(err)))

## Read until a newline or EOF is reached.
##
## ```
## # Read a line and then print it to `stdout`
## line_str = Tcp.read_line!(stream)?
## Stdout.line(line_str)?
## ```
##
## If found, the newline is included as the last character in the [Str].
##
read_line! : Stream => Result Str [TcpReadErr StreamErr, TcpReadBadUtf8 _]
read_line! = |stream|
    bytes = read_until!(stream, '\n')?

    Str.from_utf8(bytes)
    |> Result.map_err(TcpReadBadUtf8)

## Writes bytes to a TCP stream.
##
## ```
## # Writes the bytes 1, 2, 3
## Tcp.write!(stream, [1, 2, 3])?
## ```
##
## > To write a [Str], you can use [Tcp.write_utf8!] instead.
write! : Stream, List U8 => Result {} [TcpWriteErr StreamErr]
write! = |@Stream(stream), bytes|
    Host.tcp_write!(stream, bytes)
    |> Result.map_err(|err| TcpWriteErr(parse_stream_err(err)))

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Write "Hi from Roc!" encoded as UTF-8
## Tcp.write_utf8!(stream, "Hi from Roc!")?
## ```
##
## > To write unformatted bytes, you can use [Tcp.write!] instead.
write_utf8! : Stream, Str => Result {} [TcpWriteErr StreamErr]
write_utf8! = |stream, str|
    write!(stream, Str.to_utf8(str))

## Convert a [ConnectErr] to a [Str] you can print.
##
## ```
## when err is
##     TcpPerfomErr(TcpConnectErr(connect_err)) ->
##         Stderr.line!(Tcp.connect_err_to_str(connect_err))
## ```
##
connect_err_to_str : (ConnectErr _) -> Str
connect_err_to_str = |err|
    when err is
        PermissionDenied -> "PermissionDenied"
        AddrInUse -> "AddrInUse"
        AddrNotAvailable -> "AddrNotAvailable"
        ConnectionRefused -> "ConnectionRefused"
        Interrupted -> "Interrupted"
        TimedOut -> "TimedOut"
        Unsupported -> "Unsupported"
        Unrecognized(message) -> "Unrecognized Error: ${message}"

## Convert a [StreamErr] to a [Str] you can print.
##
## ```
## when err is
##     TcpPerformErr(TcpReadErr(err)) ->
##         err_str = Tcp.stream_err_to_str(err)
##         Stderr.line!("Error while reading: ${err_str}")
##
##     TcpPerformErr(TcpWriteErr(err)) ->
##         err_str = Tcp.stream_err_to_str(err)
##         Stderr.line!("Error while writing: ${err_str}")
## ```
##
stream_err_to_str : StreamErr -> Str
stream_err_to_str = |err|
    when err is
        StreamNotFound -> "StreamNotFound"
        PermissionDenied -> "PermissionDenied"
        ConnectionRefused -> "ConnectionRefused"
        ConnectionReset -> "ConnectionReset"
        Interrupted -> "Interrupted"
        OutOfMemory -> "OutOfMemory"
        BrokenPipe -> "BrokenPipe"
        Unrecognized(message) -> "Unrecognized Error: ${message}"
