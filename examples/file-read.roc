app "file-read"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Process,
        pf.Task.{ Task, await },
        pf.File,
        pf.Path,
    ]
    provides [main] to pf

main : Task {} []
main =
    fileName = "README.md"
    path = Path.fromStr fileName
    task =
        contents <- File.readUtf8 path |> await
        lines = Str.split contents "\n"

        Stdout.line (Str.concat "First line of \(fileName): " (List.first lines |> Result.withDefault "err"))

    Task.attempt task \result ->
        when result is
            Ok {} -> Process.exit 0
            Err err ->
                msg =
                    when err is
                        FileWriteErr _ PermissionDenied -> "PermissionDenied"
                        FileWriteErr _ Unsupported -> "Unsupported"
                        FileWriteErr _ (Unrecognized _ other) -> other
                        FileReadErr _ _ -> "Error reading file"
                        _ -> "Uh oh, there was an error!"

                {} <- Stderr.line msg |> await
                Process.exit 1
