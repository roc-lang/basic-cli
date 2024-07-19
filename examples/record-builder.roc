app [main] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout

main =
    myrecord : Task { apples : List Str, oranges : List Str } []_
    myrecord = { sequenceTasks <-
        apples: getFruit Apples,
        oranges: getFruit Oranges,
    }

    { apples, oranges } = myrecord!

    "Apples: "
    |> Str.concat (Str.joinWith apples ", ")
    |> Str.concat "\n"
    |> Str.concat "Oranges: "
    |> Str.concat (Str.joinWith oranges ", ")
    |> Stdout.line

getFruit : [Apples, Oranges] -> Task (List Str) []_
getFruit = \request ->
    when request is
        Apples -> Task.ok ["Granny Smith", "Pink Lady", "Golden Delicious"]
        Oranges -> Task.ok ["Navel", "Blood Orange", "Clementine"]

sequenceTasks : Task a err, Task b err, (a, b -> c) -> Task c err
sequenceTasks = \firstTask, secondTask, mapper ->
    first = firstTask!
    second = secondTask!

    Task.ok (mapper first second)
