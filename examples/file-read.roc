app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File

main =
    when run |> Task.result! is
        Ok {} -> Task.ok {}
        Err err ->
            msg =
                when err is
                    FileWriteErr _ PermissionDenied -> "PermissionDenied"
                    FileWriteErr _ Unsupported -> "Unsupported"
                    FileWriteErr _ (Unrecognized _ other) -> other
                    FileReadErr _ _ -> "Error reading file"
                    _ -> "Uh oh, there was an error!"

            Task.err (Exit 1 "unable to read file: $(msg)") # non-zero exit code to indicate failure

run =
    fileName = "LICENSE"
    contents = File.readUtf8! fileName
    lines = Str.splitOn contents "\n"

    Stdout.line (Str.concat "First line of $(fileName): " (List.first lines |> Result.withDefault "err"))
