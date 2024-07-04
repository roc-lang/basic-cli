module [
    Arg,
    Lib,
    withLib,
    arg,
    call,
]

import Effect
import Task exposing [Task]
import InternalTask

## Represents a shared library.
Lib := U64

## Represents a function arg.
Arg := U64

## Opens a library for ffi and perform a [Task] with it.
withLib : Str, (Lib -> Task a err) -> Task a [FfiLoadErr Str, FfiCallErr err]
withLib = \path, callback ->
    lib =
        load path
            |> Task.mapErr! FfiLoadErr

    result =
        callback lib
            |> Task.mapErr FfiCallErr
            |> Task.onErr!
                (\err ->
                    _ = close! lib
                    Task.err err
                )

    close lib
    |> Task.map \_ -> result

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

call : Lib, Str, List Arg -> Task {} *
call = \@Lib lib, fnName, args ->
    Effect.ffiCall lib fnName (List.map args \@Arg a -> a)
    |> Effect.map Ok
    |> InternalTask.fromEffect
    |> Task.onErr \_ -> crash "unreachable"

arg : a -> Task Arg *
arg = \data ->
    data
    |> Box.box
    |> Effect.ffiArg
    |> Effect.map @Arg
    |> Effect.map Ok
    |> InternalTask.fromEffect
    |> Task.onErr \_ -> crash "unreachable"

