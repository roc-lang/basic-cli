app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    Stdout.line!("What's your first name?")
    first = Stdin.line!({})

    Stdout.line!("What's your last name?")
    last = Stdin.line!({})

    Stdout.line!("Hi, ${first} ${last}! \u(1F44B)")
    Ok({})
}
