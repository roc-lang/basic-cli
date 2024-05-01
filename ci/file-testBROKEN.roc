app "file-test"
    packages { pf: "../platform/main.roc" }
    imports [
        pf.Stdout,
        pf.Task.{ Task },
        pf.File.{ WriteErr },
    ]
    provides [main] to pf

# Running should print the following to the terminal:
# ```
# Pass: expected NotFound
# Pass: expected PermissionDenied
# Pass: expected NotFound
# Pass: expected PermissionDenied
# Tests complete
# ```
main =
    attemptWriteTaskShouldError! (File.writeUtf8 "/asdf/asdf/asdf/asdf.txt" "str") "NotFound"
    attemptWriteTaskShouldError! (File.writeUtf8 "/System/asdf" "str") "PermissionDenied"
    attemptReadTaskShouldError! (File.readUtf8 "/asdf/asdf/asdf/asdf.txt") "NotFound"
    attemptReadTaskShouldError! (File.readUtf8 "/etc/master.passwd") "PermissionDenied"

    Stdout.line "Tests complete"

# File Writing test helpers
attemptWriteTaskShouldError = \task, error ->
    Task.attempt task \result ->
        when result is
            Ok {} ->
                Stdout.line (Str.concat "Fail: expected " error)

            Err (FileWriteErr _ err) ->
                got = Inspect.toStr err

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
                got = Inspect.toStr err

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
