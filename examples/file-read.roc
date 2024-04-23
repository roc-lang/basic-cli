app "file-read"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Task.{ Task, await },
        pf.File,
        pf.Path,
    ]
    provides [main] to pf

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

            _ = Stderr.line! msg

            Task.err (Exit 1) # non-zero exit code to indicate failure

run =
    fileName = "LICENSE"
    path = Path.fromStr fileName
    contents = File.readUtf8! path
    lines = Str.split contents "\n"

    Stdout.line (Str.concat "First line of $(fileName): " (List.first lines |> Result.withDefault "err"))

    
