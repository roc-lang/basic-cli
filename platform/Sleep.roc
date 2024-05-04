module [
    millis,
]

import Effect
import InternalTask
import Task exposing [Task]

## Sleep for at least the given number of milliseconds.
## This uses [rust's std::thread::sleep](https://doc.rust-lang.org/std/thread/fn.sleep.html).
##
millis : U64 -> Task {} *
millis = \n ->
    Effect.sleepMillis n
    |> Effect.map Ok
    |> InternalTask.fromEffect
