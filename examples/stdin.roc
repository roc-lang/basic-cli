app "example-stdin"
    packages { pf: "../src/main.roc" }
    imports [
        pf.Stdout,
        pf.Stderr,
        pf.Stdin,
        pf.Task.{ Task },
    ]
    provides [main] to pf

main =
    {} <- Stdout.line "Enter a series of number characters (0-9):" |> Task.await
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

    bytesRead <- Stdin.bytes |> Task.await

    numberBytes =
        List.walk bytesRead [] \bytes, b ->
            if b >= '0' && b <= '9' then
                List.append bytes b
            else
                bytes

    Task.succeed numberBytes
