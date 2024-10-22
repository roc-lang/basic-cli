platform "cli"
    requires {} { main : {} => Result {} [Exit I32 Str]_ }
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
        Tcp,
        Url,
        Utc,
        Sleep,
        Cmd,
        Tty,
    ]
    packages {}
    imports []
    provides [mainForHost]

import Stderr

mainForHost : {} => Result {} I32
mainForHost = \{} ->
    Task.attempt main \res ->
        when res is
            Ok {} -> Ok {}
            Err (Exit code str) ->
                if Str.isEmpty str then
                    Err code
                else
                    Stderr.line str
                    |> Task.onErr \_ -> Err code
                    |> Task.await \{} -> Err code

            Err err ->
                Stderr.line
                    """
                    Program exited with error:
                        $(Inspect.toStr err)

                    Tip: If you do not want to exit on this error, use `Task.mapErr` to handle the error.
                    Docs for `Task.mapErr`: <https://www.roc-lang.org/packages/basic-cli/Task#mapErr>
                    """
                |> Task.onErr \_ -> Err 1
                |> Task.await \_ -> Err 1
