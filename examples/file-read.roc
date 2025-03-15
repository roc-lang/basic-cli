app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.File

main! = |_args|

    run!({})
    ? |err|
        msg =
            when err is
                FileWriteErr(_, PermissionDenied) -> "PermissionDenied"
                FileWriteErr(_, Unsupported) -> "Unsupported"
                FileWriteErr(_, Unrecognized(_, other)) -> other
                FileReadErr(_, _) -> "Error reading file"
                _ -> "Uh oh, there was an error!"

        Exit(1, "unable to read file: ${msg}") # non-zero exit code to indicate failure

    crash "test"
    
    Ok({})

run! = |{}|
    file_name = "LICENSE"
    contents = File.read_utf8!(file_name)?
    lines = Str.split_on(contents, "\n")

    Stdout.line!(Str.concat("First line of ${file_name}: ", (List.first(lines) |> Result.with_default("err"))))
