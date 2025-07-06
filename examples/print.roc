app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Arg exposing [Arg]

# Printing to stdout and stderr

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|
    
    # # Print a string to stdout
    Stdout.line!("Hello, world!")?

    # # Print without a newline
    Stdout.write!("No newline after me.")?

    # # Print a string to stderr
    Stderr.line!("Hello, error!")?

    # # Print a string to stderr without a newline
    Stderr.write!("Err with no newline after.")?

    # # Print a list to stdout
    ["Foo", "Bar", "Baz"]
    |> List.for_each_try!(|str| Stdout.line!(str))
    
    # Use List.map! if you want to apply an effectful function that returns something.
    # Use List.map_try! if you want to apply an effectful function that returns a Result.
