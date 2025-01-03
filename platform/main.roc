platform "cli"
    requires {} { main! : List Arg.Arg => Result {} [Exit I32 Str]_ }
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
        Sqlite,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Arg
import Stderr
import InternalArg

main_for_host! : List InternalArg.ArgToAndFromHost => I32
main_for_host! = \raw_args ->

    args =
        raw_args
        |> List.map InternalArg.to_os_raw
        |> List.map Arg.from_os_raw

    when main! args is
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
