app "tcp-client"
    packages { pf: "../src/main.roc" }
    imports [pf.Tcp, pf.Task.{ Task, await }, pf.Stdout, pf.Stdin, pf.Stderr, pf.Process]
    provides [main] to pf

main : Task {} []
main =
    task =
        stream <- Tcp.withConnect "127.0.0.1" 8080
        _ <- Stdout.line "Connected!" |> await

        Task.loop {} \_ -> Task.map (tick stream) Step

    Task.attempt task \result ->
        when result is
            Ok _ ->
                Process.exit 0

            Err (TcpConnectErr err) ->
                dbg
                    err

                Stderr.line
                    """
                    Failed to connect.

                    If you don't have anything listening on port 8080, run: 
                    $ nc -l 8080
                    """

            Err (TcpPerformErr (BadUtf8 _)) ->
                Stderr.line "Received non-UTF8 data"

            Err (TcpPerformErr err) ->
                dbg
                    err

                Stderr.line "Something went wrong while reading or writing data"

tick : Tcp.Stream -> Task.Task {} _
tick = \stream ->
    _ <- Stdout.write "> " |> await
    outMsg <- Stdin.line |> await
    _ <- Tcp.writeUtf8 "\(outMsg)\n" stream |> await

    inMsg <- Tcp.readUtf8 stream |> await
    Stdout.line "< \(inMsg)"
