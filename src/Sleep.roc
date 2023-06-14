interface Sleep
    exposes [
        millis,
    ]
    imports [Effect, InternalTask, Task.{ Task }]

## Sleep for a given number of milliseconds
millis : U64 -> Task {} *
millis = \n ->
    Effect.sleepMillis n
    |> Effect.map Ok
    |> InternalTask.fromEffect
