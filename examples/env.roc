app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Env

main =
    when run |> Task.result! is
        Ok letters ->
            joinedLetters = Str.joinWith letters " "

            Stdout.line "Your favorite letters are: $(joinedLetters)"

        Err _ ->
            Stderr.line "I couldn't find your favorite letters in the environment variables!"

run =
    Env.decode "EDITOR"
    |> Task.await (\editor -> Stdout.line "Your favorite editor is $(editor)!")
    |> Task.await (\{} -> Env.decode "SHLVL")
    |> Task.await
        (\lvl ->
            when lvl is
                1u8 -> Stdout.line "You're running this in a root shell!"
                n ->
                    lvlStr = Num.toStr n

                    Stdout.line "Your current shell level is $(lvlStr)!")
    |> Task.await \{} -> Env.decode "LETTERS"

