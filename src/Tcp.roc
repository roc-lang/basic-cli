interface Tcp
    exposes [
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
    imports [Effect, Task.{ Task }, InternalTask, InternalTcp]

Stream : InternalTcp.Stream

ConnectErr : InternalTcp.ConnectErr

StreamErr : InternalTcp.StreamErr

## Opens a TCP conenction to a remote host and perform a [Task] with it.
##
##     # Connect to localhost:8080 and send "Hi from Roc!"
##     stream <- Tcp.withConnect "localhost" 8080
##     Tcp.writeUtf8 "Hi from Roc!" stream
##
## Examples of valid hostnames:
##  - 127.0.0.1
##  - ::1
##  - localhost
##  - roc-lang.org
##
## The connection is automatically closed after the [Task] is completed.
withConnect : Str, U16, (Stream -> Task {} err) -> Task {} [TcpConnectErr ConnectErr, TcpPerformErr err]
withConnect = \hostname, port, callback ->
    stream <- connect hostname port
        |> Task.mapFail TcpConnectErr
        |> Task.await

    {} <- callback stream
        |> Task.mapFail TcpPerformErr
        |> Task.onFail (\err -> 
            _ <- close stream |> Task.await
            Task.fail err
        )
        |> Task.await

    close stream

connect : Str, U16 -> Task Stream ConnectErr
connect = \host, port ->
    Effect.tcpConnect host port
    |> Effect.map InternalTcp.fromConnectResult
    |> InternalTask.fromEffect

close : Stream -> Task {} *
close = \stream ->
    Effect.tcpClose stream
    |> Effect.map \{} -> Ok {}
    |> InternalTask.fromEffect

## Read up to a number of bytes from the TCP stream.
##
##     received <- File.readUpTo 64 stream |> await
##
## If you need a [Str], you can use [Str.fromUtf8]:
##
##     Str.fromUtf8 received
##
## To read an exact number of bytes or fail, you can use [Tcp.readExactly] instead.
readUpTo : Nat, Stream -> Task (List U8) [TcpReadErr StreamErr]
readUpTo = \bytesToRead, stream ->
    Effect.tcpReadUpTo bytesToRead stream
    |> Effect.map InternalTcp.fromReadResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpReadErr

## Read an exact number of bytes or fail.
##
##     File.readExactly 64 stream
##
## [TcpUnexpectedEOF] is returned if the stream ends before the specfied number of bytes is reached.
readExactly : Nat, Stream -> Task (List U8) [TcpReadErr StreamErr, TcpUnexpectedEOF]
readExactly = \bytesToRead, stream ->
    Effect.tcpReadExactly bytesToRead stream
    |> Effect.map
        (\result ->
            when result is
                Read bytes ->
                    Ok bytes

                UnexpectedEOF ->
                    Err TcpUnexpectedEOF

                Error err ->
                    Err (TcpReadErr err)
        )
    |> InternalTask.fromEffect

## Read until a delimiter or EOF is reached.
##
##     # Read until null terminator
##     File.readUntil 0 stream
##
## If found, the delimiter is included as the last byte.
##
## To read until a newline is found, you can use [Tcp.readLine] which conveniently decodes to a [Str].
readUntil : U8, Stream -> Task (List U8) [TcpReadErr StreamErr]
readUntil = \byte, stream ->
    Effect.tcpReadUntil byte stream
    |> Effect.map InternalTcp.fromReadResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpReadErr

## Read until a newline or EOF is reached.
##
##     File.readLine stream
##
## If found, the newline is included as the last character in the [Str].
readLine : Stream -> Task Str [TcpReadErr StreamErr, TcpReadBadUtf8 _]
readLine = \stream ->
    bytes <- readUntil '\n' stream |> Task.await

    Str.fromUtf8 bytes
    |> Result.mapErr TcpReadBadUtf8
    |> Task.fromResult

## Writes bytes to a TCP stream.
##
##     # Writes the bytes 1, 2, 3
##     Tcp.writeBytes [1, 2, 3] stream
##
## To write a [Str], you can use [Tcp.writeUtf8] instead.
write : List U8, Stream -> Task {} [TcpWriteErr StreamErr]
write = \bytes, stream ->
    Effect.tcpWrite bytes stream
    |> Effect.map InternalTcp.fromWriteResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpWriteErr

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
##     # Write "Hi from Roc!" encoded as UTF-8
##     Tcp.writeUtf8 "Hi from Roc!" stream
##
## To write unformatted bytes, you can use [Tcp.write] instead.
writeUtf8 : Str, Stream -> Task {} [TcpWriteErr StreamErr]
writeUtf8 = \str, stream ->
    write (Str.toUtf8 str) stream

## Convert a [ConnectErr] to a [Str] you can print.
##
##     when err is
##         TcpPerfomErr (TcpConnectErr connectErr) ->
##             Stderr.line (Tcp.connectErrToStr connectErr)
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
        Unrecognized code message ->
            codeStr = Num.toStr code
            "Unrecognized Error: \(codeStr) - \(message)"

## Convert a [StreamErr] to a [Str] you can print.
##
##     when err is
##         TcpPerformErr (TcpReadErr err) ->
##             errStr = Tcp.streamErrToStr err
##             Stderr.line "Error while reading: \(errStr)"
##
##         TcpPerformErr (TcpWriteErr err) ->
##             errStr = Tcp.streamErrToStr err
##             Stderr.line "Error while writing: \(errStr)"
##
streamErrToStr : StreamErr -> Str
streamErrToStr = \err ->
    when err is
        PermissionDenied -> "PermissionDenied"
        ConnectionRefused -> "ConnectionRefused"
        ConnectionReset -> "ConnectionReset"
        Interrupted -> "Interrupted"
        OutOfMemory -> "OutOfMemory"
        BrokenPipe -> "BrokenPipe"
        Unrecognized code message ->
            codeStr = Num.toStr code
            "Unrecognized Error: \(codeStr) - \(message)"

