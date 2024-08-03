module [
    Stream,
    connect,
    readUpTo,
    readExactly,
    readUntil,
    readLine,
    write,
    writeUtf8,
    ConnectErr,
    connectErrToStr,
    StreamErr,
    streamErrToStr,
]

import PlatformTask

unexpectedEofErrorMessage = "UnexpectedEof"

## Represents a TCP stream.
Stream := PlatformTask.TcpStream

## Represents errors that can occur when connecting to a remote host.
ConnectErr : [
    PermissionDenied,
    AddrInUse,
    AddrNotAvailable,
    ConnectionRefused,
    Interrupted,
    TimedOut,
    Unsupported,
    Unrecognized Str,
]

parseConnectErr : Str -> ConnectErr
parseConnectErr = \err ->
    when err is
        "ErrorKind::PermissionDenied" -> PermissionDenied
        "ErrorKind::AddrInUse" -> AddrInUse
        "ErrorKind::AddrNotAvailable" -> AddrNotAvailable
        "ErrorKind::ConnectionRefused" -> ConnectionRefused
        "ErrorKind::Interrupted" -> Interrupted
        "ErrorKind::TimedOut" -> TimedOut
        "ErrorKind::Unsupported" -> Unsupported
        other -> Unrecognized other

## Represents errors that can occur when performing a [Task] with a [Stream].
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

parseStreamErr : Str -> StreamErr
parseStreamErr = \err ->
    when err is
        "StreamNotFound" -> StreamNotFound
        "ErrorKind::PermissionDenied" -> PermissionDenied
        "ErrorKind::ConnectionRefused" -> ConnectionRefused
        "ErrorKind::ConnectionReset" -> ConnectionReset
        "ErrorKind::Interrupted" -> Interrupted
        "ErrorKind::OutOfMemory" -> OutOfMemory
        "ErrorKind::BrokenPipe" -> BrokenPipe
        other -> Unrecognized other

## Opens a TCP connection to a remote host.
##
## ```
## # Connect to localhost:8080
## stream = Tcp.connect! "localhost" 8080
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
connect : Str, U16 -> Task Stream ConnectErr
connect = \host, port ->
    PlatformTask.tcpConnect host port
        |> Task.map @Stream
        |> Task.mapErr! parseConnectErr

## Read up to a number of bytes from the TCP stream.
##
## ```
## # Read up to 64 bytes from the stream and convert to a Str
## received <- File.readUpTo stream 64 |> Task.await
## Str.fromUtf8 received
## ```
##
## > To read an exact number of bytes or fail, you can use [Tcp.readExactly] instead.
readUpTo : Stream, U64 -> Task (List U8) [TcpReadErr StreamErr]
readUpTo = \@Stream stream, bytesToRead ->
    PlatformTask.tcpReadUpTo stream bytesToRead
    |> Task.mapErr \err -> TcpReadErr (parseStreamErr err)

## Read an exact number of bytes or fail.
##
## ```
## File.readExactly stream 64
## ```
##
## `TcpUnexpectedEOF` is returned if the stream ends before the specfied number of bytes is reached.
##
readExactly : Stream, U64 -> Task (List U8) [TcpReadErr StreamErr, TcpUnexpectedEOF]
readExactly = \@Stream stream, bytesToRead ->
    PlatformTask.tcpReadExactly stream bytesToRead
    |> Task.mapErr \err ->
        if err == unexpectedEofErrorMessage then
            TcpUnexpectedEOF
        else
            TcpReadErr (parseStreamErr err)

## Read until a delimiter or EOF is reached.
##
## ```
## # Read until null terminator
## File.readUntil stream 0
## ```
##
## If found, the delimiter is included as the last byte.
##
## > To read until a newline is found, you can use [Tcp.readLine] which
## conveniently decodes to a [Str].
readUntil : Stream, U8 -> Task (List U8) [TcpReadErr StreamErr]
readUntil = \@Stream stream, byte ->
    PlatformTask.tcpReadUntil stream byte
        |> Task.mapErr! \err -> TcpReadErr (parseStreamErr err)

## Read until a newline or EOF is reached.
##
## ```
## # Read a line and then print it to `stdout`
## lineStr <- File.readLine stream |> Task.await
## Stdout.line lineStr
## ```
##
## If found, the newline is included as the last character in the [Str].
##
readLine : Stream -> Task Str [TcpReadErr StreamErr, TcpReadBadUtf8 _]
readLine = \stream ->
    bytes = readUntil! stream '\n'

    Str.fromUtf8 bytes
    |> Result.mapErr TcpReadBadUtf8
    |> Task.fromResult

## Writes bytes to a TCP stream.
##
## ```
## # Writes the bytes 1, 2, 3
## Tcp.writeBytes stream [1, 2, 3]
## ```
##
## > To write a [Str], you can use [Tcp.writeUtf8] instead.
write : Stream, List U8 -> Task {} [TcpWriteErr StreamErr]
write = \@Stream stream, bytes ->
    PlatformTask.tcpWrite stream bytes
        |> Task.mapErr! \err -> TcpWriteErr (parseStreamErr err)

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Write "Hi from Roc!" encoded as UTF-8
## Tcp.writeUtf8 stream "Hi from Roc!"
## ```
##
## > To write unformatted bytes, you can use [Tcp.write] instead.
writeUtf8 : Stream, Str -> Task {} [TcpWriteErr StreamErr]
writeUtf8 = \stream, str ->
    write stream (Str.toUtf8 str)

## Convert a [ConnectErr] to a [Str] you can print.
##
## ```
## when err is
##     TcpPerfomErr (TcpConnectErr connectErr) ->
##         Stderr.line (Tcp.connectErrToStr connectErr)
## ```
##
connectErrToStr : ConnectErr -> Str
connectErrToStr = \err ->
    when err is
        PermissionDenied -> "PermissionDenied"
        AddrInUse -> "AddrInUse"
        AddrNotAvailable -> "AddrNotAvailable"
        ConnectionRefused -> "ConnectionRefused"
        Interrupted -> "Interrupted"
        TimedOut -> "TimedOut"
        Unsupported -> "Unsupported"
        Unrecognized message -> "Unrecognized Error: $(message)"

## Convert a [StreamErr] to a [Str] you can print.
##
## ```
## when err is
##     TcpPerformErr (TcpReadErr err) ->
##         errStr = Tcp.streamErrToStr err
##         Stderr.line "Error while reading: $(errStr)"
##
##     TcpPerformErr (TcpWriteErr err) ->
##         errStr = Tcp.streamErrToStr err
##         Stderr.line "Error while writing: $(errStr)"
## ```
##
streamErrToStr : StreamErr -> Str
streamErrToStr = \err ->
    when err is
        StreamNotFound -> "StreamNotFound"
        PermissionDenied -> "PermissionDenied"
        ConnectionRefused -> "ConnectionRefused"
        ConnectionReset -> "ConnectionReset"
        Interrupted -> "Interrupted"
        OutOfMemory -> "OutOfMemory"
        BrokenPipe -> "BrokenPipe"
        Unrecognized message -> "Unrecognized Error: $(message)"
