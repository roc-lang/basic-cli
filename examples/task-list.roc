app "task-list"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main : Task {} I32
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
