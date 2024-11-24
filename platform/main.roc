platform "cli"
    requires {} { main! : {} => Result {} [Exit I32 Str]_ }
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
        Locale,
    ]
    packages {}
    imports []
    provides [mainForHost!]

import Stderr

mainForHost! : I32 => Result {} I32
mainForHost! = \_ ->
    when main! {} is
        Ok {} -> Ok {}

        Err (Exit code msg) ->
            if Str.isEmpty msg then
                Err code
            else
                when Stderr.line! msg is
                    Ok {} -> Err code
                    Err (StderrErr _) -> Err code

        Err msg ->

            helpMsg =
                """
                Program exited with error:
                    $(Inspect.toStr msg)

                Tip: If you do not want to exit on this error, use `Result.mapErr` to handle the error. Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """

            when Stderr.line! helpMsg is
                Ok {} -> Err 1
                Err (StderrErr _) -> Err 1
