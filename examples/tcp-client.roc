app [main!] { pf: platform "../platform/main.roc" }

import pf.Tcp
import pf.Stdout
import pf.Stdin
import pf.Stderr
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Simple TCP client in Roc.
# Connects to a server on localhost:8085, reads user input from stdin,
# sends it to the server, and prints the server's response.

main! : List Arg => Result {} _
main! = |_args|

    tcp_stream = Tcp.connect!("127.0.0.1", 8085)?

    Stdout.line!("Connected!")?

    loop!(
        {},
        |_| Result.map_ok(tick!(tcp_stream), Step),
    )
    |> Result.on_err!(handle_err!)

## Read from stdin, send to the server, and print the response.
tick! : Tcp.Stream => Result {} _
tick! = |tcp_stream|
    Stdout.write!("> ")?

    out_msg = Stdin.line!({})?

    Tcp.write_utf8!(tcp_stream, "${out_msg}\n")?

    in_msg = Tcp.read_line!(tcp_stream)?

    Stdout.line!("< ${in_msg}")


loop! : state, (state => Result [Step state, Done done] err) => Result done err
loop! = |state, fn!|
    when fn!(state) is
        Err(err) -> Err(err)
        Ok(Done(done)) -> Ok(done)
        Ok(Step(next)) -> loop!(next, fn!)


handle_err! : []_ => Result {} _
handle_err! = |error|
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

        other_err -> Stderr.line!("Unhandled error: ${Inspect.to_str(other_err)}")
