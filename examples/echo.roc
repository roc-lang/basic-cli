app [main] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main =
    Stdout.line! "Shout into this cave and hear the echo!"

    Task.loop {} tick

tick : {} -> Task [Step {}, Done {}] _
tick = \{} ->
    when Stdin.line |> Task.result! is
        Ok str ->
            Stdout.line! (echo str)
            Task.ok (Step {})

        Err (StdinErr EndOfFile) ->
            Stdout.line! (echo "Received end of input (EOF).")
            Task.ok (Done {})

        Err (StdinErr err) ->
            Stdout.line! (echo "Unable to read input $(Inspect.toStr err)")
            Task.ok (Done {})

echo : Str -> Str
echo = \shout ->
    silence = \length ->
        List.repeat ' ' length

    shout
    |> Str.toUtf8
    |> List.mapWithIndex
        (\_, i ->
            length = (List.len (Str.toUtf8 shout) - i)
            phrase = (List.splitAt (Str.toUtf8 shout) length).before

            List.concat (silence (if i == 0 then 2 * length else length)) phrase)
    |> List.join
    |> Str.fromUtf8
    |> Result.withDefault ""

expect
    message = "hello!"
    echoedMessage = echo message

    echoedMessage == "            hello!     hello    hell   hel  he h"
