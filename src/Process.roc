interface Process
    exposes [exit]
    imports [Task.{ Task }, InternalTask, Effect]

## Terminates the current process with the specified exit code. This function
## will never return and will immediately terminate the current process.
##
## ```
## {} <- Stderr.line "Exiting right now!" |> Task.await
## Process.exit 1
## ```
exit : U8 -> Task {} *
exit = \code ->
    Effect.processExit code
    |> Effect.map \_ -> Ok {}
    |> InternalTask.fromEffect
