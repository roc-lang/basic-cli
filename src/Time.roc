interface Time
    exposes [
        now,
    ]
    imports [Effect, InternalTask, Task.{ Task }]

## Milliseconds since UNIX EPOCH
now : Task U128 *
now =
    Effect.posixTime
    |> Effect.map Ok
    |> InternalTask.fromEffect
