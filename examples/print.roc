app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr

# Printing to stdout and stderr

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    # Print a string to stdout
    Stdout.line!("Hello, world!")

    # Print without a newline
    Stdout.write!("No newline after me.")

    # Print a string to stderr
    Stderr.line!("Hello, error!")

    # Print a string to stderr without a newline
    Stderr.write!("Err with no newline after.")

    # Print a list to stdout
    List.for_each!(["Foo", "Bar", "Baz"], |str| {
        Stdout.line!(str)
    })

    Ok({})
}
