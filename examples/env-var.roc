app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.Env

# How to read environment variables with Env.decode

main! = \_args ->

    editor = try Env.decode! "EDITOR"

    try Stdout.line! "Your favorite editor is $(editor)!"

    # Env.decode! does not return the same type everywhere.
    # The type is determined based on type inference.
    # Here `Str.joinWith` forces the type that Env.decode! returns to be `List Str`
    joined_letters =
        Env.decode! "LETTERS"
        |> Result.map \letters -> Str.joinWith letters " "
        |> try

    Stdout.line! "Your favorite letters are: $(joined_letters)"
