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

main : Task {} I32
main =
    fileName = "LICENSE"
    path = Path.fromStr fileName
    task =
        contents <- File.readUtf8 path |> await
        lines = Str.split contents "\n"

        Stdout.line (Str.concat "First line of $(fileName): " (List.first lines |> Result.withDefault "err"))

    Task.attempt task \result ->
        when result is
            Ok {} -> Task.ok {}
            Err err ->
                msg =
                    when err is
                        FileWriteErr _ PermissionDenied -> "PermissionDenied"
                        FileWriteErr _ Unsupported -> "Unsupported"
                        FileWriteErr _ (Unrecognized _ other) -> other
                        FileReadErr _ _ -> "Error reading file"
                        _ -> "Uh oh, there was an error!"

                {} <- Stderr.line msg |> await

                Task.err 1 # 1 is an exit code to indicate failure
