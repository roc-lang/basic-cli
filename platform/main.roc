platform "cli"
    requires {} { main! : List Str => Result {} [Exit I32 Str]_ }
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

import Arg
import Stderr

mainForHost! : I32 => I32
mainForHost! = \_ ->
    args = Arg.list! {}

    when main! args is
        Ok {} -> 0
        Err (Exit code msg) ->
            if Str.isEmpty msg then
                code
            else
                _ = Stderr.line! msg
                code

        Err msg ->
            helpMsg =
                """
                Program exited with error:
                    $(Inspect.toStr msg)

                Tip: If you do not want to exit on this error, use `Result.mapErr` to handle the error. Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """

            _ = Stderr.line! helpMsg
            1
