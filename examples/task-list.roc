app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

# To run this example: check the README.md in this folder

main! = |_args|
    # Prints out each of the authors
    print!(["Foo", "Bar", "Baz"])

print! : List Str => Result {} _
print! = |authors|
    when authors is
        [] -> Ok({})
        [author, .. as rest] ->
            Stdout.line!(author)?
            print!(rest)
