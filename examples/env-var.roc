app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env

# How to read environment variables with Env.var!

main! = |_args| {
    result = Env.var!("EDITOR")

    match result {
        Ok(editor) => {
            _r = Stdout.line!("Your favorite editor is ${editor}!")
            Ok({})
        }
        Err(VarNotFound(name)) => {
            _r = Stdout.line!("${name} is not set")
            Ok({})
        }
    }
}
