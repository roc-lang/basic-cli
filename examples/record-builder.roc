app "record-builder"
    packages {
        pf: "../src/main.roc",
    }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =
    myrecord : Task { apples : List Str, oranges : List Str } []
    myrecord = Task.succeed {
        apples: <- getFruit Apples |> Task.batch,
        oranges: <- getFruit Oranges |> Task.batch,
    }

    { apples, oranges } <- myrecord |> Task.await

    "Apples: "
    |> Str.concat (Str.joinWith apples ", ")
    |> Str.concat "\n"
    |> Str.concat "Oranges: "
    |> Str.concat (Str.joinWith oranges ", ")
    |> Stdout.line

getFruit : [Apples, Oranges] -> Task (List Str) []
getFruit = \request ->
    when request is
        Apples -> Task.succeed ["Granny Smith", "Pink Lady", "Golden Delicious"]
        Oranges -> Task.succeed ["Navel", "Blood Orange", "Clementine"]
