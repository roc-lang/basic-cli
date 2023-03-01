interface Socket 
    exposes [Stream, withConnect, read, write]
    imports [Effect, Task.{ Task }, InternalTask]

Stream := Nat

withConnect : Str, (Stream -> Task {} a) -> Task {} a
withConnect = \addr, callback ->
    stream <- connect addr |> Task.await
    result <- callback stream |> Task.attempt
    {} <- close stream |> Task.await
    Task.fromResult result


connect : Str -> Task Stream *
connect = \addr ->
    Effect.tcpConnect addr
    |> Effect.map (\ptr -> Ok (@Stream ptr))
    |> InternalTask.fromEffect


close : Stream -> Task {} *
close = \@Stream ptr ->
    Effect.tcpClose ptr
    |> Effect.map (\_ -> Ok {})
    |> InternalTask.fromEffect


read : Stream -> Task Str *
read = \@Stream ptr ->
    Effect.tcpRead ptr
    |> Effect.map (\str -> Ok str)
    |> InternalTask.fromEffect


write : Str, Stream -> Task {} *
write = \str, @Stream ptr ->
    Effect.tcpWrite str ptr
    |> Effect.map (\_ -> Ok {})
    |> InternalTask.fromEffect