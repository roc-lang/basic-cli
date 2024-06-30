module [
    Stream,
    withConnect,
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

import Effect
import Task exposing [Task]
import InternalTask

unexpectedEofErrorMessage = "UnexpectedEof"

## Represents a TCP stream.
Stream := U64

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

## Opens a TCP connection to a remote host and perform a [Task] with it.
##
## ```
## # Connect to localhost:8080 and send "Hi from Roc!"
## stream <- Tcp.withConnect "localhost" 8080
## Tcp.writeUtf8 "Hi from Roc!" stream
## ```
##
## The connection is automatically closed after the [Task] is completed. Examples of
## valid hostnames:
##  - `127.0.0.1`
##  - `::1`
##  - `localhost`
##  - `roc-lang.org`
##
withConnect : Str, U16, (Stream -> Task a err) -> Task a [TcpConnectErr ConnectErr, TcpPerformErr err]
withConnect = \hostname, port, callback ->
    stream =
        connect hostname port
            |> Task.mapErr! TcpConnectErr

    result =
        callback stream
            |> Task.mapErr TcpPerformErr
            |> Task.onErr!
                (\err ->
                    _ = close! stream
                    Task.err err
                )

    close stream
    |> Task.map \_ -> result

connect : Str, U16 -> Task Stream ConnectErr
connect = \host, port ->
    Effect.tcpConnect host port
    |> Effect.map \res ->
        res
        |> Result.map @Stream
        |> Result.mapErr parseConnectErr
    |> InternalTask.fromEffect

close : Stream -> Task {} *
close = \@Stream stream ->
    Effect.tcpClose stream
    |> InternalTask.fromEffect

## Read up to a number of bytes from the TCP stream.
##
## ```
## # Read up to 64 bytes from the stream and convert to a Str
## received <- File.readUpTo 64 stream |> Task.await
## Str.fromUtf8 received
## ```
##
## > To read an exact number of bytes or fail, you can use [Tcp.readExactly] instead.
readUpTo : Stream, U64 -> Task (List U8) [TcpReadErr StreamErr]
readUpTo = \@Stream stream, bytesToRead ->
    Effect.tcpReadUpTo stream bytesToRead
    |> Effect.map \res ->
        res
        |> Result.mapErr parseStreamErr
        |> Result.mapErr TcpReadErr
    |> InternalTask.fromEffect

## Read an exact number of bytes or fail.
##
## ```
## File.readExactly 64 stream
## ```
##
## `TcpUnexpectedEOF` is returned if the stream ends before the specfied number of bytes is reached.
##
readExactly : Stream, U64 -> Task (List U8) [TcpReadErr StreamErr, TcpUnexpectedEOF]
readExactly = \@Stream stream, bytesToRead ->
    Effect.tcpReadExactly stream bytesToRead
    |> Effect.map \res ->
        res
        |> Result.mapErr \err ->
            if err == unexpectedEofErrorMessage then
                TcpUnexpectedEOF
            else
                TcpReadErr (parseStreamErr err)
    |> InternalTask.fromEffect

## Read until a delimiter or EOF is reached.
##
## ```
## # Read until null terminator
## File.readUntil 0 stream
## ```
##
## If found, the delimiter is included as the last byte.
##
## > To read until a newline is found, you can use [Tcp.readLine] which
## conveniently decodes to a [Str].
readUntil : Stream, U8 -> Task (List U8) [TcpReadErr StreamErr]
readUntil = \@Stream stream, byte ->
    Effect.tcpReadUntil stream byte
    |> Effect.map \res ->
        res
        |> Result.mapErr parseStreamErr
        |> Result.mapErr TcpReadErr
    |> InternalTask.fromEffect

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
## Tcp.writeBytes [1, 2, 3] stream
## ```
##
## > To write a [Str], you can use [Tcp.writeUtf8] instead.
write : Stream, List U8 -> Task {} [TcpWriteErr StreamErr]
write = \@Stream stream, bytes ->
    Effect.tcpWrite stream bytes
    |> Effect.map \res ->
        res
        |> Result.mapErr parseStreamErr
        |> Result.mapErr TcpWriteErr
    |> InternalTask.fromEffect

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
## ```
## # Write "Hi from Roc!" encoded as UTF-8
## Tcp.writeUtf8 "Hi from Roc!" stream
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
        Unrecognized message ->
            "Unrecognized Error: $(message)"

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
        Unrecognized message ->
            "Unrecognized Error: $(message)"
