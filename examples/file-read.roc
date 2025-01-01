app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.File

main! = \_args ->
    when run! {} is
        Ok {} -> Ok {}
        Err err ->
            msg =
                when err is
                    FileWriteErr _ PermissionDenied -> "PermissionDenied"
                    FileWriteErr _ Unsupported -> "Unsupported"
                    FileWriteErr _ (Unrecognized _ other) -> other
                    FileReadErr _ _ -> "Error reading file"
                    _ -> "Uh oh, there was an error!"

            Err (Exit 1 "unable to read file: $(msg)") # non-zero exit code to indicate failure

run! = \{} ->
    file_name = "LICENSE"
    contents = try File.read_utf8! file_name
    lines = Str.splitOn contents "\n"

    Stdout.line! (Str.concat "First line of $(file_name): " (List.first lines |> Result.withDefault "err"))
