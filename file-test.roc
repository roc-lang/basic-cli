app "file-test"
    packages { pf: "src/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.File.{ WriteErr },
        pf.Path.{ Path },
    ]
    provides [main] to pf

# Should print the following to the terminal
# ```
# Pass: expected NotFound
# Pass: expected PermissionDenied
# Pass: expected NotFound
# Pass: expected PermissionDenied
# Tests complete
# ```
main : Task {} []
main =
    {} <- attemptWriteTaskShouldError (File.writeUtf8 (Path.fromStr "/asdf/asdf/asdf/asdf.txt") "str") "NotFound" |> Task.await
    {} <- attemptWriteTaskShouldError (File.writeUtf8 (Path.fromStr "/System/asdf") "str") "PermissionDenied" |> Task.await

    {} <- attemptReadTaskShouldError (File.readUtf8 (Path.fromStr "/asdf/asdf/asdf/asdf.txt")) "NotFound" |> Task.await
    {} <- attemptReadTaskShouldError (File.readUtf8 (Path.fromStr "/etc/master.passwd")) "PermissionDenied" |> Task.await

    Stdout.line "Tests complete"

# File Writing test helpers
attemptWriteTaskShouldError = \task, error ->
    Task.attempt task \result ->
        when result is
            Ok {} ->
                Stdout.line (Str.concat "Fail: expected " error)

            Err (FileWriteErr _ err) ->
                got = File.writeErrToStr err

                if got == error then
                    Stdout.line (Str.concat "Pass: expected " got)
                else
                    msg = ["Fail: expected ", error, " got ", got] |> Str.joinWith ""

                    Stdout.line msg

# File Reading test helpers
attemptReadTaskShouldError = \task, error ->
    Task.attempt task \result ->
        when result is
            Ok _ ->
                Stdout.line (Str.concat "Fail: expected " error)

            Err (FileReadErr _ err) ->
                got = File.readErrToStr err

                if got == error then
                    Stdout.line (Str.concat "Pass: expected " got)
                else
                    msg = ["Fail: expected ", error, " got ", got] |> Str.joinWith ""

                    Stdout.line msg

            Err (FileReadUtf8Err _ _) ->
                if error == "FileReadUtf8Err" then
                    Stdout.line "Pass: expected FileReadUtf8Err"
                else
                    msg = ["Fail: expected ", error, " got FileReadUtf8Err"] |> Str.joinWith ""

                    Stdout.line msg
