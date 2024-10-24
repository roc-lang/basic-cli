app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! : {} => Result {} _
main! = \{} ->
    _ = Stdout.line! "\nLet's count down from 3 together - all you have to do is press <ENTER>."
    _ = Stdin.line!
    loop! 3 tick!

tick! = \n ->
    if n == 0 then
        _ = Stdout.line! "🎉 SURPRISE! Happy Birthday! 🎂"
        Ok (Done {})
    else
        _ = Stdout.line! (n |> Num.toStr |> \s -> "$(s)...")
        _ = Stdin.line! {}
        Ok (Step (n - 1))

loop! : state, (state => Result [Done done, Step state] err) => Result done err
loop! = \state, stepFn! ->
    result = stepFn! state
    when result is
        Ok (Step next) -> loop! next stepFn!
        Ok (Done done) -> Ok done
        Err err -> Err err
