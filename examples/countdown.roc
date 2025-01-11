app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdin
import pf.Stdout

main! = \_args ->
    Stdout.line!("\nLet's count down from 3 together - all you have to do is press <ENTER>.")?
    _ = Stdin.line!({})
    tick!(3)

tick! = \n ->
    if n == 0 then
        Stdout.line!("🎉 SURPRISE! Happy Birthday! 🎂")?
        Ok({})
    else
        Stdout.line!((n |> Num.to_str |> \s -> "${s}..."))?
        _ = Stdin.line!({})
        tick!((n - 1))
