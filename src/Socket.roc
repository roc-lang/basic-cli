interface Socket 
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


readBytes : Stream -> Task (List U8) *
readBytes = \@Stream ptr ->
    Effect.tcpRead ptr
    |> Effect.map \bytes -> Ok bytes
    |> InternalTask.fromEffect


readUtf8 : Stream -> Task Str [SocketReadUtf8Err _]
readUtf8 = \@Stream ptr ->
    Effect.tcpRead ptr
    |> Effect.map \bytes -> 
        Str.fromUtf8 bytes
        |> Result.mapErr \err -> SocketReadUtf8Err err
    |> InternalTask.fromEffect


writeBytes : List U8, Stream -> Task {} *
writeBytes = \bytes, @Stream ptr ->
    Effect.tcpWrite bytes ptr
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect
    

writeUtf8 : Str, Stream -> Task {} *
writeUtf8 = \str, @Stream ptr ->
    Str.toUtf8 str
    |> Effect.tcpWrite ptr
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect