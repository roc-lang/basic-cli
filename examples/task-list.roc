app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout

main =

    authors : List Str
    authors = [
        "Foo",
        "Bar",
        "Baz",
    ]

    # Print out each of the authors (in reverse)
    _ =
        authors
            |> List.map Stdout.line
            |> Task.seq!
    # Also prints out each of the authors
    Task.forEach! authors Stdout.line
