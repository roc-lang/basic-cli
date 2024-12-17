app [main!] {
    pf: platform "../platform/main.roc",
}

import pf.Stdout

main! : List Str => Result {} _
main! = \args ->
    # get the second argument, the first is the executable's path
    argResult = List.get args 1 |> Result.mapErr (\_ -> ZeroArgsGiven)

    when argResult is
        Err ZeroArgsGiven ->
            Err (Exit 1 "Error ZeroArgsGiven:\n\tI expected one argument, but I got none.\n\tRun the app like this: `roc main.roc -- input.txt`")

        Ok firstArgument ->
            Stdout.line! "received argument: $(firstArgument)"
