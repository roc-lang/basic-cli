app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Arg exposing [Arg]

# How to read environment variables with Env.decode

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|

    editor = Env.decode!("EDITOR")?

    Stdout.line!("Your favorite editor is ${editor}!")?

    # Env.decode! does not return the same type everywhere.
    # The type is determined based on type inference.
    # Here `Str.join_with` forces the type that Env.decode! returns to be `List Str`
    joined_letters =
        Env.decode!("LETTERS")
        |> Result.map_ok(|letters| Str.join_with(letters, " "))?

    Stdout.line!("Your favorite letters are: ${joined_letters}")
