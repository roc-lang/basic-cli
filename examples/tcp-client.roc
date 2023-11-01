app "tcp-client"
    packages { pf: "../src/main.roc" }
    imports [pf.Tcp, pf.Task.{ Task, await }, pf.Stdout, pf.Stdin, pf.Stderr]
    provides [main] to pf

main : Task {} I32
main =
    task =
        stream <- Tcp.withConnect "127.0.0.1" 8085
        _ <- Stdout.line "Connected!" |> await

        Task.loop {} \_ -> Task.map (tick stream) Step

    Task.attempt task \result ->
        when result is
            Ok _ ->
                Task.ok {}

            Err (TcpConnectErr err) ->
                errStr = Tcp.connectErrToStr err
                Stderr.line
                    """
                    Failed to connect: \(errStr)

                    If you don't have anything listening on port 8085, run: 
                    $ nc -l 8085
                    If you want an echo server you can run:
                    $ ncat -e $(which cat) -l 8085
                    """

            Err (TcpPerformErr (TcpReadBadUtf8 _)) ->
                Stderr.line "Received invalid UTF-8 data"

            Err (TcpPerformErr (TcpReadErr err)) ->
                errStr = Tcp.streamErrToStr err
                Stderr.line "Error while reading: \(errStr)"

            Err (TcpPerformErr (TcpWriteErr err)) ->
                errStr = Tcp.streamErrToStr err
                Stderr.line "Error while writing: \(errStr)"

tick : Tcp.Stream -> Task.Task {} _
tick = \stream ->
    _ <- Stdout.write "> " |> await

    input <- Stdin.line |> await

    outMsg = when input is
        End -> "Received end of input (EOF)."
        Input msg -> msg

    _ <- Tcp.writeUtf8 "\(outMsg)\n" stream |> await

    inMsg <- Tcp.readLine stream |> await
    Stdout.line "< \(inMsg)"
