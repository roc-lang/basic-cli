interface Tcp 
    exposes [
        Stream, 
        withConnect,
        readBytes,
        readUtf8,
        writeBytes,
        writeUtf8,
    ]
    imports [Effect, Task.{ Task }, InternalTask]

Stream := Nat

## Opens a TCP conenction to a remote host and perform a [Task] with it.
##
##     # Connect to localhost:8080 and send "Hi from Roc!"
##     stream <- Tcp.withConnect "localhost" 8080
##     Tcp.writeUtf8 "Hi from Roc!"
## 
## This closes the connection after the [Task] is completed.
withConnect : Str, U16, (Stream -> Task {} a) -> Task {} a
withConnect = \host, port, callback ->
    stream <- connect host port |> Task.await
    result <- callback stream |> Task.attempt
    {} <- close stream |> Task.await
    Task.fromResult result


connect : Str, U16 -> Task Stream *
connect = \host, port ->
    Effect.tcpConnect host port
    |> Effect.map \ptr -> Ok (@Stream ptr)
    |> InternalTask.fromEffect


close : Stream -> Task {} *
close = \@Stream ptr ->
    Effect.tcpClose ptr
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect


## Reads all available bytes in the TCP Stream.
##
##     # Read all the bytes available
##     File.readBytes stream
##
## To read a [Str], you can use `Tcp.readUtf8` instead.
readBytes : Stream -> Task (List U8) *
readBytes = \@Stream ptr ->
    Effect.tcpRead ptr
    |> Effect.map \bytes -> Ok bytes
    |> InternalTask.fromEffect

## Reads a [Str] from all the available bytes in the TCP Stream.
##
##     # Read all the bytes available
##     File.readUtf8 stream
##
## To read unformatted bytes, you can use `Tcp.readBytes` instead.
readUtf8 : Stream -> Task Str [SocketReadUtf8Err _]
readUtf8 = \@Stream ptr ->
    Effect.tcpRead ptr
    |> Effect.map \bytes -> 
        Str.fromUtf8 bytes
        |> Result.mapErr \err -> SocketReadUtf8Err err
    |> InternalTask.fromEffect

## Writes bytes to a TCP stream.
##
##     # Writes the bytes 1, 2, 3 
##     Tcp.writeBytes [1, 2, 3] stream
##
## To write a [Str], you can use [Tcp.writeUtf8] instead.
writeBytes : List U8, Stream -> Task {} *
writeBytes = \bytes, @Stream ptr ->
    Effect.tcpWrite bytes ptr
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect
    

## Writes a [Str] to a TCP stream, encoded as [UTF-8](https://en.wikipedia.org/wiki/UTF-8).
##
##     # Write "Hi from Roc!" encoded as UTF-8
##     Tcp.writeUtf8 "Hi from Roc!" stream
##
## To write unformatted bytes, you can use [Tcp.writeBytes] instead.
writeUtf8 : Str, Stream -> Task {} *
writeUtf8 = \str, @Stream ptr ->
    Str.toUtf8 str
    |> Effect.tcpWrite ptr
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect