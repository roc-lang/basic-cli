platform "cli"
    requires {} { main : Task {} [] }
    exposes []
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

connectErr = AddrInUse
streamErr = ConnectionReset
tcpResult = Success {}

mainForHost : Task {} [] as Fx
mainForHost =
    when { connectErr, streamErr, tcpResult } is
        _ ->
            main

