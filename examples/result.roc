app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout


main! = \_args ->
    when check_file! "good" is
        Ok Good -> Stdout.line! "GOOD"
        Ok Bad -> Stdout.line! "BAD"
        Err IOError -> Stdout.line! "IOError"

check_file! : Str => Result [Good, Bad] [IOError]
check_file! = \str ->
    if str == "good" then
        Ok Good
    else if str == "bad" then
        Ok Bad
    else
        Err IOError
