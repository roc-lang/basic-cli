interface Tcp
    exposes [
        Stream,
        withConnect,
        readBytes,
        readUtf8,
        writeBytes,
        writeUtf8,
        errToStr,
        connectErrToStr,
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

## Reads all available bytes in the TCP Stream.
##
##     # Read all the bytes available
##     File.readBytes stream
##
## To read a [Str], you can use `Tcp.readUtf8` instead.
readBytes : Stream -> Task (List U8) [TcpReadErr StreamErr]
readBytes = \stream ->
    Effect.tcpRead stream
    |> Effect.map InternalTcp.fromReadResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpReadErr

## Reads a [Str] from all the available bytes in the TCP Stream.
##
##     # Read all the bytes available
##     File.readUtf8 stream
##
## To read unformatted bytes, you can use `Tcp.readBytes` instead.
readUtf8 : Stream -> Task Str [TcpReadErr StreamErr, TcpReadBadUtf8 _]
readUtf8 = \stream ->
    Effect.tcpRead stream
    |> Effect.map \result ->
        InternalTcp.fromReadResult result
        |> Result.mapErr TcpReadErr
        |> Result.try \bytes ->
            Str.fromUtf8 bytes
            |> Result.mapErr \err -> TcpReadBadUtf8 err
    |> InternalTask.fromEffect

## Writes bytes to a TCP stream.
##
##     # Writes the bytes 1, 2, 3
##     Tcp.writeBytes [1, 2, 3] stream
##
## To write a [Str], you can use [Tcp.writeUtf8] instead.
writeBytes : List U8, Stream -> Task {} [TcpWriteErr StreamErr]
writeBytes = \bytes, stream ->
    Effect.tcpWrite bytes stream
    |> Effect.map InternalTcp.fromWriteResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpWriteErr

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
##     # Write "Hi from Roc!" encoded as UTF-8
##     Tcp.writeUtf8 "Hi from Roc!" stream
##
## To write unformatted bytes, you can use [Tcp.writeBytes] instead.
writeUtf8 : Str, Stream -> Task {} [TcpWriteErr StreamErr]
writeUtf8 = \str, stream ->
    Str.toUtf8 str
    |> Effect.tcpWrite stream
    |> Effect.map InternalTcp.fromWriteResult
    |> InternalTask.fromEffect
    |> Task.mapFail TcpWriteErr

errToStr :
    [
        TcpConnectErr ConnectErr,
        TcpReadErr StreamErr,
        TcpReadBadUtf8 _,
        TcpWriteErr StreamErr,
    ]
    -> Str
errToStr = \tag ->
    when tag is
        TcpConnectErr err ->
            errStr = Tcp.connectErrToStr err
            "TcpConnectErr: \(errStr)"

        TcpReadBadUtf8 _ ->
            "TcpReadBadUtf8"

        TcpReadErr err ->
            errStr = streamErrToStr err
            "TcpReadErr: \(errStr)"

        TcpWriteErr err ->
            errStr = streamErrToStr err
            "TcpWriteErr: \(errStr)"

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

