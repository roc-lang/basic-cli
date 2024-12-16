app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = \{} ->
    Stdout.line!? "\nLet's count down from 3 together - all you have to do is press <ENTER>."
    _ = Stdin.line! {}
    tick! 3

tick! = \n ->
    if n == 0 then
        Stdout.line!? "🎉 SURPRISE! Happy Birthday! 🎂"
        Ok {}
    else
        Stdout.line!? (n |> Num.toStr |> \s -> "$(s)...")
        _ = Stdin.line! {}
        tick! (n - 1)
