app "tcp-client"
    packages { pf: "../platform/main.roc" }
    imports [pf.Tcp, pf.Task.{ Task, await }, pf.Stdout, pf.Stdin, pf.Stderr]
    provides [main] to pf

main : Task {} I32
main = run |> Task.onErr handleErr

handleErr = \error ->
    when error is 
        (TcpConnectErr err) ->
            errStr = Tcp.connectErrToStr err
            Stderr.line
                """
                Failed to connect: $(errStr)

                If you don't have anything listening on port 8085, run: 
                \$ nc -l 8085

                If you want an echo server you can run:
                $ ncat -e \$(which cat) -l 8085
                """

        (TcpPerformErr (TcpReadBadUtf8 _)) ->
            Stderr.line "Received invalid UTF-8 data"

        (TcpPerformErr (TcpReadErr err)) ->
            errStr = Tcp.streamErrToStr err
            Stderr.line "Error while reading: $(errStr)"

        (TcpPerformErr (TcpWriteErr err)) ->
            errStr = Tcp.streamErrToStr err
            Stderr.line "Error while writing: $(errStr)"

        other -> Stderr.line "Got other error: $(Inspect.toStr other)"

run = 
    stream <- Tcp.withConnect "127.0.0.1" 8085
            
    Stdout.line! "Connected!"

    Task.loop {} \_ -> Task.map (tick stream) Step


tick : Tcp.Stream -> Task.Task {} _
tick = \stream ->
    Stdout.write! "> "

    outMsg = Stdin.line!
    
    Tcp.writeUtf8! "$(outMsg)\n" stream

    inMsg = Tcp.readLine! stream

    Stdout.line! "< $(inMsg)"
