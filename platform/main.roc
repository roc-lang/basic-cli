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
    provides [main_for_host!]

import Stderr

main_for_host! : I32 => I32
main_for_host! = \_ ->
    when main! {} is
        Ok {} -> 0
        Err (Exit code msg) ->
            if Str.isEmpty msg then
                code
            else
                _ = Stderr.line! msg
                code

        Err msg ->
            help_msg =
                """
                Program exited with error:
                    $(Inspect.toStr msg)

                Tip: If you do not want to exit on this error, use `Result.mapErr` to handle the error. Docs for `Result.mapErr`: <https://www.roc-lang.org/builtins/Result#mapErr>
                """

            _ = Stderr.line! help_msg
            1
