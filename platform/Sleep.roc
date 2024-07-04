module [millis]

import PlatformTask

## Sleep for at least the given number of milliseconds.
## This uses [rust's std::thread::sleep](https://doc.rust-lang.org/std/thread/fn.sleep.html).
##
millis : U64 -> Task {} []_
millis = \n ->
    PlatformTask.sleepMillis n
        |> Task.result!
        |> Result.withDefault {}
        |> Task.ok
