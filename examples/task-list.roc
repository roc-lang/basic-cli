app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

main! = \{} ->
    # Prints out each of the authors
    forEach! [ "Foo", "Bar", "Baz" ] Stdout.line!

forEach! : List a, (a => Result {} err) => Result {} err
forEach! = \l, f! ->
    when l is
        [] -> Ok {}
        [x, .. as xs] ->
            try f! x
            forEach! xs f!
