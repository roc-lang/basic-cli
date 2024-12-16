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
            errStr = Tcp.connect_err_to_str err
            Stderr.line!
                """
                Failed to connect: $(errStr)

                If you don't have anything listening on port 8085, run:
                \$ nc -l 8085

                If you want an echo server you can run:
                $ ncat -e \$(which cat) -l 8085
                """

        TcpReadBadUtf8 _ ->
            Stderr.line! "Received invalid UTF-8 data"

        TcpReadErr err ->
            errStr = Tcp.streamErrToStr err
            Stderr.line! "Error while reading: $(errStr)"

        TcpWriteErr err ->
            errStr = Tcp.streamErrToStr err
            Stderr.line! "Error while writing: $(errStr)"

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

    outMsg = try Stdin.line! {}

    try Tcp.writeUtf8! stream "$(outMsg)\n"

    inMsg = try Tcp.readLine! stream

    Stdout.line! "< $(inMsg)"

loop! : state, (state => Result [Step state, Done done] err) => Result done err
loop! = \state, fn! ->
    when fn! state is
        Err err -> Err err
        Ok (Done done) -> Ok done
        Ok (Step next) -> loop! next fn!
