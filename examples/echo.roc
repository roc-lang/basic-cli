app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = \{} -> tick! {}

tick! = \{} ->
    when Stdin.line! {} is
        Ok str ->
            try Stdout.line! (echo str)
            tick! {}

        Err EndOfFile ->
            try Stdout.line! (echo "Received end of input (EOF).")
            Ok {}

        Err (StdinErr err) ->
            try Stdout.line! (echo "Unable to read input $(Inspect.toStr err)")
            Ok {}

echo : Str -> Str
echo = \shout ->
    silence = \length -> List.repeat ' ' length

    shout
    |> Str.toUtf8
    |> List.mapWithIndex \_, i ->
        length = (List.len (Str.toUtf8 shout) - i)
        phrase = (List.split (Str.toUtf8 shout) length).before

        List.concat (silence (if i == 0 then 2 * length else length)) phrase
    |> List.join
    |> Str.fromUtf8
    |> Result.withDefault ""

expect
    message = "hello!"
    echoedMessage = echo message

    echoedMessage == "            hello!     hello    hell   hel  he h"
