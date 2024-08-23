app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Task exposing [Task]

# How to read environment variables with Env.decode

main =
    run
    |> Task.mapErr \err -> Exit 1 "Error: $(Inspect.toStr err)"

run : Task {} _
run =
    editor =
        Env.decode "EDITOR"
            |> Task.mapErr! \_ -> FailedToGetEnvVarEDITOR

    Stdout.line! "Your favorite editor is $(editor)!"

    # Env.decode! does not return the same type everywhere.
    # The type is determined based on type inference.
    # Here `Str.joinWith` forces the type that Env.decode! returns to be `List Str`
    letters =
        Env.decode "LETTERS"
            |> Task.mapErr! \_ -> FailedToGetEnvVarLETTERS
    joinedLetters = Str.joinWith letters " "

    Stdout.line! "Your favorite letters are: $(joinedLetters)"
