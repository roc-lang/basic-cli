module [
    Socket,
    BindErr,
    SocketErr,
    bind,
    receiveUpTo,
]

import Effect
import Task exposing [Task]
import InternalTask
import InternalUdp

Socket : InternalUdp.Socket

BindErr : InternalUdp.BindErr

SocketErr : InternalUdp.SocketErr

bind : Str, U16 -> Task Socket [Something BindErr]
bind = \host, port ->
    Effect.udpBind host port
    |> Effect.map InternalUdp.fromBindResult
    |> InternalTask.fromEffect
    |> Task.mapErr Something

receiveUpTo : U64, Socket -> Task (List U8) [UdpReceiveErr SocketErr]
receiveUpTo = \bytesToRead, socket ->
    Effect.udpReceiveUpTo bytesToRead socket
      |> Effect.map InternalUdp.fromReceiveResult
      |> InternalTask.fromEffect
      |> Task.mapErr UdpReceiveErr
