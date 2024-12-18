app [main!] { pf: platform "../platform/main.roc" }

import pf.Tcp
import pf.Stdout
import pf.Stdin
import pf.Stderr

main! = \{} ->
    when run! {} is
        Ok {} -> Ok {}
        Err err -> handle_err! err

handle_err! : []_ => Result {} _
handle_err! = \error ->
    when error is
        TcpConnectErr err ->
            err_str = Tcp.connect_err_to_str err
            Stderr.line!
                """
                Failed to connect: $(err_str)

                If you don't have anything listening on port 8085, run:
                \$ nc -l 8085

                If you want an echo server you can run:
                $ ncat -e \$(which cat) -l 8085
                """

        TcpReadBadUtf8 _ ->
            Stderr.line! "Received invalid UTF-8 data"

        TcpReadErr err ->
            err_str = Tcp.stream_err_to_str err
            Stderr.line! "Error while reading: $(err_str)"

        TcpWriteErr err ->
            err_str = Tcp.stream_err_to_str err
            Stderr.line! "Error while writing: $(err_str)"

        other -> Stderr.line! "Got other error: $(Inspect.toStr other)"

run! : {} => Result {} _
run! = \{} ->

    stream = try Tcp.connect! "127.0.0.1" 8085

    try Stdout.line! "Connected!"

    loop! {} \_ ->
        Result.map (tick! stream) Step

tick! : Tcp.Stream => Result {} _
tick! = \stream ->
    try Stdout.write! "> "

    out_msg = try Stdin.line! {}

    try Tcp.write_utf8! stream "$(out_msg)\n"

    in_msg = try Tcp.read_line! stream

    Stdout.line! "< $(in_msg)"

loop! : state, (state => Result [Step state, Done done] err) => Result done err
loop! = \state, fn! ->
    when fn! state is
        Err err -> Err err
        Ok (Done done) -> Ok done
        Ok (Step next) -> loop! next fn!
