app "socket-client"
    packages { pf: "../src/main.roc" }
    imports [pf.Socket, pf.Task.{ Task, await }, pf.Stdout, pf.Stdin]
    provides [main] to pf

main : Task {} []
main =
    stream <- Socket.withConnect "127.0.0.1" 8080
    _ <- Stdout.line "Connected!" |> await

    Task.loop {} \_ -> Task.map (tick stream) Step

tick : Socket.Stream -> Task.Task {} []
tick = \stream ->
    _ <- Stdout.write "> " |> await 
    outMsg <- Stdin.line |> await
    _ <- Socket.write "\(outMsg)\n" stream |> await
    
    inMsg <- Socket.read stream |> await
    Stdout.line "< \(inMsg)"