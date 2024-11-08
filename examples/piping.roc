app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stdin

# Try piping in some text like this: `echo -e "test\n123" | roc piping.roc`
main! = \{} ->
    lines = try loop! 0 count!
    Stdout.line! "I read $(Num.toStr lines) lines from stdin."

count! = \n ->
    when Stdin.line! {} is
        Ok _ -> Step (n + 1) |> Ok
        Err _ -> Done n |> Ok

loop! : state, (state => Result [Step state, Done done] err) => Result done err
loop! = \state, fn! ->
    when fn! state is
        Err err -> Err err
        Ok (Done done) -> Ok done
        Ok (Step next) -> loop! next fn!
