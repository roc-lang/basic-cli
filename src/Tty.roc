interface Tty
    exposes [ 
        disableRawMode,
        enableRawMode,
    ]
    imports [Effect, Task.{ Task }, InternalTask]

disableRawMode : Task {} *
disableRawMode =
    Effect.ttyModeCanonical
    |> Effect.map Ok
    |> InternalTask.fromEffect

enableRawMode : Task {} *
enableRawMode =
    Effect.ttyModeRaw
    |> Effect.map Ok
    |> InternalTask.fromEffect