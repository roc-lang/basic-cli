interface Socket 
    exposes [Stream, connect, read, write]
    imports [Effect, Task.{ Task }, InternalTask]

Stream := Nat

connect : Str -> Task Stream *
connect = \addr ->
    Effect.tcpConnect addr
    |> Effect.map (\ptr -> Ok (@Stream ptr))
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

