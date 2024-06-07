app "udp-client"
    packages { pf: platform "../platform/main.roc" }
    imports [pf.Udp, pf.Task.{ Task, await }, pf.Stdout, pf.Stderr]
    provides [main] to pf

main = run |> Task.onErr handleErr

handleErr = \_error ->
    Stderr.line "butt"

run =
    Stdout.line! "Starting Connection"
    socket = Udp.bind! "127.0.0.1" 8085
    Stdout.line! "Connected!"

    # Not yet in lib.rs
    # Task.loop {} \_ -> Task.map (tick socket) Step


getString = \bytes ->
    Str.fromUtf8 bytes |> Task.fromResult!

tick = \socket ->
    inBytes = Udp.receiveUpTo! 64 socket

    inMsg = getString inBytes!

    Stdout.line "> $(inMsg)"
