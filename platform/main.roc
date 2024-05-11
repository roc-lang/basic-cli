platform "cli"
    requires {} { main : Task {} [Exit I32 Str]_ }
    exposes [
        Path,
        Arg,
        Dir,
        Env,
        File,
        FileMetadata,
        Http,
        Stderr,
        Stdin,
        Stdout,
        Task,
        Tcp,
        Url,
        Utc,
        Sleep,
        Cmd,
        Tty,
    ]
    packages {}
    imports [
        Task.{ Task },
        # TODO: Use Stderr.line unqualified once that no longer (incorrectly) results in a "Stderr is not imported" error
        Stderr.{ line },
    ]
    provides [mainForHost]

mainForHost : Task {} I32 as Fx
mainForHost =
    Task.attempt main \res ->
        when res is
            Ok {} -> Task.ok {}
            Err (Exit code str) ->
                if Str.isEmpty str then
                    Task.err code
                else
                    line str
                    |> Task.onErr \_ -> Task.err code
                    |> Task.await \{} -> Task.err code

            Err err ->
                line
                    """
                    Program exited early with error:
                        $(Inspect.toStr err)

                    Tip: If you do not want an early exit on error, use `Task.mapErr` to handle the error.
                    For an example: <https://github.com/roc-lang/basic-cli/blob/main/examples/http-get-json.roc>
                    """
                |> Task.onErr \_ -> Task.err 1
                |> Task.await \_ -> Task.err 1
