platform "cli"
    requires {} { main! : List Arg.Arg => Result {} [Exit I32 Str]_ }
    exposes [
        Path,
        Arg,
        Dir,
        Env,
        File,
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
        Random,
    ]
    packages {}
    imports []
    provides [main_for_host!]

import Arg
import Stderr
import InternalArg

main_for_host! : List InternalArg.ArgToAndFromHost => I32
main_for_host! = |raw_args|

    args =
        raw_args
        |> List.map(InternalArg.to_os_raw)
        |> List.map(Arg.from_os_raw)

    when main!(args) is
        Ok({}) -> 0
        Err(Exit(code, msg)) ->
            if Str.is_empty(msg) then
                code
            else
                _ = Stderr.line!(msg)
                code

        Err(err) ->
            err_str = Inspect.to_str(err)

            clean_err_str =
                # Inspect adds parentheses around errors, which are unnecessary here.
                if Str.starts_with(err_str, "(") and Str.ends_with(err_str, ")") then
                    err_str
                    |> Str.replace_first("(", "")
                    |> Str.replace_last(")", "")
                else
                    err_str

            help_msg =
                """

                Program exited with error:

                ❌ ${clean_err_str}
                """

            _ = Stderr.line!(help_msg)
            1
