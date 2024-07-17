app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task, await]
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
                    BadUtf8 _ _ -> "Error parsing file as utf8"
                    _ -> "Uh oh, there was an error!"

            Task.err (Exit 1 "unable to read file: $(msg)") # non-zero exit code to indicate failure

run =
    fileName = "LICENSE"
    contents = File.mmap! fileName
    contentsStr = Str.fromUtf8 contents |> Task.fromResult!
    lines = Str.split contentsStr "\n"

    Stdout.line (Str.concat "First line of $(fileName): " (List.first lines |> Result.withDefault "err"))
