app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout

main! = \{} ->
    { apples, oranges } = try
        { Result.map2 <-
            apples: getFruit! Apples |> Result.map joinStrs,
            oranges: getFruit! Oranges |> Result.map joinStrs,
        }

    Stdout.line! "Apples: $(apples)\nOranges: $(oranges)"

joinStrs = \fruits -> Str.joinWith fruits ", "

## This doesn't actually perform any effects, but we can imagine that it does
## for the sake of this example, maybe it fetches data from a server or reads a file.
getFruit! : [Apples, Oranges] => Result (List Str) []
getFruit! = \request ->
    when request is
        Apples -> Ok ["Granny Smith", "Pink Lady", "Golden Delicious"]
        Oranges -> Ok ["Navel", "Blood Orange", "Clementine"]
