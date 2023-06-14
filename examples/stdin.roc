app "time"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Stdin,
        pf.Task.{Task},
    ]
    provides [main] to pf

main =
    numberBytes <- takeNumberBytes |> Task.await

    if List.isEmpty numberBytes then
        Stderr.line "Expected a series of number characters (0-9)"
    else
        when Str.fromUtf8 numberBytes is
            Ok nStr -> 
                Stdout.line "Got number \(nStr)"
            Err _ ->
                Stderr.line "Error, bad utf8"

takeNumberBytes : Task (List U8) *
takeNumberBytes = 
    Task.loop [] \bytes ->
        b <- Stdin.byte |> Task.await
        
        if b >= '0' && b <= '9' then 
            Task.succeed (Step (List.append bytes b))
        else 
            Task.succeed (Done bytes)