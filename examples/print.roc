app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr

# Printing to stdout and stderr

main! = |_args| {
    # Print a string to stdout
    match Stdout.line!("Hello, world!") { _ => {} }

    # Print without a newline
    match Stdout.write!("No newline after me.") { _ => {} }

    # Print a string to stderr
    match Stderr.line!("Hello, error!") { _ => {} }

    # Print a string to stderr without a newline
    match Stderr.write!("Err with no newline after.") { _ => {} }

    # Print a list to stdout
    List.for_each!(["Foo", "Bar", "Baz"], |str| {
        match Stdout.line!(str) { _ => {} }
    })

    Ok({})
}
