app [main!] { pf: platform "../platform/main.roc" }

import pf.Tcp
import pf.Stdout
import pf.Stdin
import pf.Stderr

# To run this example: check the README.md in this folder

main! = \_args ->
    when run!({}) is
        Ok({}) -> Ok({})
        Err(err) -> handle_err!(err)

handle_err! : []_ => Result {} _
handle_err! = \error ->
    when error is
        TcpConnectErr(err) ->
            err_str = Tcp.connect_err_to_str(err)
            Stderr.line!(
                """
                Failed to connect: ${err_str}

                If you don't have anything listening on port 8085, run:
                \$ nc -l 8085

                If you want an echo server you can run:
                $ ncat -e \$(which cat) -l 8085
                """,
            )

        TcpReadBadUtf8(_) ->
            Stderr.line!("Received invalid UTF-8 data")

        TcpReadErr(err) ->
            err_str = Tcp.stream_err_to_str(err)
            Stderr.line!("Error while reading: ${err_str}")

        TcpWriteErr(err) ->
            err_str = Tcp.stream_err_to_str(err)
            Stderr.line!("Error while writing: ${err_str}")

        other -> Stderr.line!("Got other error: ${Inspect.to_str(other)}")

run! : {} => Result {} _
run! = \{} ->

    stream = Tcp.connect!("127.0.0.1", 8085)?

    Stdout.line!("Connected!")?

    loop!(
        {},
        \_ -> Result.map(tick!(stream), Step),
    )

tick! : Tcp.Stream => Result {} _
tick! = \stream ->
    Stdout.write!("> ")?

    out_msg = Stdin.line!({})?

    Tcp.write_utf8!(stream, "${out_msg}\n")?

    in_msg = Tcp.read_line!(stream)?

    Stdout.line!("< ${in_msg}")

loop! : state, (state => Result [Step state, Done done] err) => Result done err
loop! = \state, fn! ->
    when fn!(state) is
        Err(err) -> Err(err)
        Ok(Done(done)) -> Ok(done)
        Ok(Step(next)) -> loop!(next, fn!)
