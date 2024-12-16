app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! = \{} ->
    # Prints out each of the authors
    print! ["Foo", "Bar", "Baz"]

print! : List Str => Result {} _
print! = \authors ->
    when authors is
        [] -> Ok {}
        [author, .. as rest] ->
            Stdout.line!? author
            print! rest
