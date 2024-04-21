app "result"
    packages { pf: "../platform/main.roc" }
    imports [pf.Stdout, pf.Task.{ Task }]
    provides [main] to pf

main : Task {} I32
main =
    when checkFile "good" |> Task.result! is
        Ok Good -> Stdout.line "GOOD"
        Ok Bad -> Stdout.line "BAD"
        Err IOError -> Stdout.line "IOError"

checkFile : Str -> Task [Good, Bad] [IOError]
checkFile = \str ->
    if str == "good" then 
        Task.ok Good 
    else if str == "bad" then 
        Task.ok Bad 
    else 
        Task.err IOError