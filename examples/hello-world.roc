app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! = |_args| {
    _r = Stdout.line!("Hello, World!")
    Ok({})
}
