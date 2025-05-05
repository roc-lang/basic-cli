app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout
import pf.Arg exposing [Arg]

# How to handle command line arguments in Roc.

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |raw_args|

    args = List.map(raw_args, Arg.display)

    # get the second argument, the first is the executable's path
    when List.get(args, 1) |> Result.map_err(|_| ZeroArgsGiven) is
        Err(ZeroArgsGiven) ->
            Err(Exit(1, "Error ZeroArgsGiven:\n\tI expected one argument, but I got none.\n\tRun the app like this: `roc main.roc -- input.txt`"))

        Ok(first_arg) ->
            Stdout.line!("received argument: ${first_arg}")
