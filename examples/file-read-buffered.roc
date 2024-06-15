app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task, await]
import pf.File

main =
    handle = File.openBuffered! "LICENSE"

    state = Task.loop!
        { linesRead: 0, bytesRead: 0 }
        (processLine handle)

    Stdout.line "Done reading, got $(Inspect.toStr state)"

State : { linesRead : U64, bytesRead : U64 }

processLine : File.FD -> (State -> Task [Step State, Done State] _)
processLine = \handle -> \{ linesRead, bytesRead } ->
        when File.readLine handle |> Task.result! is
            Ok bytes ->
                Task.ok (Step { linesRead: linesRead + 1, bytesRead: bytesRead + (List.len bytes |> Num.intCast) })

            Err _ ->
                Task.ok (Done { linesRead, bytesRead })
