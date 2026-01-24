app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env

# How to read environment variables with Env.var!

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    editor = Env.var!("EDITOR")

    if Str.is_empty(editor) {
        Stdout.line!("EDITOR is not set")
    } else {
        Stdout.line!("Your favorite editor is ${editor}!")
    }

    Ok({})
}
