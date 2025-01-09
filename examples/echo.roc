app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdin
import pf.Stdout

main! = \_args ->
    Stdout.line!("Shout into this cave and hear the echo!")?
    tick!({})

tick! : {} => Result {} [StdoutErr _]
tick! = \{} ->
    when Stdin.line!({}) is
        Ok(str) ->
            Stdout.line!(echo(str))?
            tick!({})

        Err(EndOfFile) ->
            Stdout.line!(echo("Received end of input (EOF)."))?
            Ok({})

        Err(StdinErr(err)) ->
            Stdout.line!(echo("Unable to read input $(Inspect.to_str(err))"))?
            Ok({})

echo : Str -> Str
echo = \shout ->
    silence = \length -> List.repeat(' ', length)

    shout
    |> Str.to_utf8
    |> List.map_with_index(
        \_, i ->
            length = (List.len(Str.to_utf8(shout)) - i)
            phrase = (List.split_at(Str.to_utf8(shout), length)).before

            List.concat(silence((if i == 0 then 2 * length else length)), phrase),
    )
    |> List.join
    |> Str.from_utf8
    |> Result.with_default("")

expect
    message = "hello!"
    echoed = echo(message)
    echoed == "            hello!     hello    hell   hel  he h"
