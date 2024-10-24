app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env

# How to read environment variables with Env.decode

main! = \{} ->
    run! {}
    |> Result.mapErr \err -> Exit 1 "Error: $(Inspect.toStr err)"

run! : {} => Result {} _
run! = \{} ->
    editor =
        Env.decode! "EDITOR"
            |> Result.mapErr? \_ -> FailedToGetEnvVarEDITOR

    _ = Stdout.line! "Your favorite editor is $(editor)!"

    # Env.decode! does not return the same type everywhere.
    # The type is determined based on type inference.
    # Here `Str.joinWith` forces the type that Env.decode! returns to be `List Str`
    letters =
        Env.decode! "LETTERS"
            |> Result.mapErr? \_ -> FailedToGetEnvVarLETTERS

    joinedLetters = Str.joinWith letters " "

    Stdout.line! "Your favorite letters are: $(joinedLetters)"
