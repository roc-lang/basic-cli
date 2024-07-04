module [
    Lib,
    withLib,
    call,
]

import Effect
import Task exposing [Task]
import InternalTask

## Represents a shared library.
Lib := U64

## Opens a library for ffi and perform a [Task] with it.
withLib : Str, (Lib -> Task a err) -> Task a [FfiLoadErr Str, FfiCallErr err]
withLib = \path, callback ->
    lib =
        load path
            |> Task.mapErr! FfiLoadErr

    out =
        callback lib
            |> Task.mapErr FfiCallErr
            |> Task.onErr!
                (\err ->
                    _ = close! lib
                    Task.err err
                )

    close lib
    |> Task.map \_ -> out

load : Str -> Task Lib Str
load = \path ->
    Effect.ffiLoad path
    |> InternalTask.fromEffect
    |> Task.map @Lib

close : Lib -> Task {} *
close = \@Lib lib ->
    Effect.ffiClose lib
    |> Effect.map Ok
    |> InternalTask.fromEffect

call : Lib, Str, a -> Task b *
call = \@Lib lib, fnName, args ->
    Effect.ffiCall lib fnName (Box.box args)
    |> Effect.map Box.unbox
    |> Effect.map Ok
    |> InternalTask.fromEffect
    |> Task.onErr \_ -> crash "unreachable"
