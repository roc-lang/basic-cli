app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout

# To run this example: check the README.md in this folder

main! = \_args ->
    { apples, oranges } = { Result.map2 <-
        apples: get_fruit!(Apples) |> Result.map(join_strs),
        oranges: get_fruit!(Oranges) |> Result.map(join_strs),
    }?

    Stdout.line!("Apples: $(apples)\nOranges: $(oranges)")

join_strs = \fruits -> Str.join_with(fruits, ", ")

## This doesn't actually perform any effects, but we can imagine that it does
## for the sake of this example, maybe it fetches data from a server or reads a file.
get_fruit! : [Apples, Oranges] => Result (List Str) *
get_fruit! = \request ->
    when request is
        Apples -> Ok(["Granny Smith", "Pink Lady", "Golden Delicious"])
        Oranges -> Ok(["Navel", "Blood Orange", "Clementine"])
