module [
    Lib,
    withLib,
    call,
    callNoReturn,
]

import Effect
import Task exposing [Task]
import InternalTask

## Represents a shared library.
Lib := U64

## Opens a library for ffi and perform a [Task] with it.
withLib : Str, (Lib -> Task a [FfiLoadErr Str]err) -> Task a [FfiLoadErr Str]err
withLib = \path, callback ->
    lib =
        load path
            |> Task.mapErr! FfiLoadErr

    out =
        callback lib
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

call : Lib, Str, a -> Task b [FfiCallErr Str]
call = \@Lib lib, fnName, args ->
    Effect.ffiCall lib fnName (Box.box args)
    |> InternalTask.fromEffect
    |> Task.map Box.unbox
    |> Task.mapErr FfiCallErr

callNoReturn : Lib, Str, a -> Task {} [FfiCallErr Str]
callNoReturn = \@Lib lib, fnName, args ->
    Effect.ffiCallNoReturn lib fnName (Box.box args)
    |> InternalTask.fromEffect
    |> Task.mapErr FfiCallErr
