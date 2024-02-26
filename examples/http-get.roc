app "http-get"
    packages { pf: "../platform/main.roc" }
    imports [pf.Http, pf.Task.{ Task }, pf.Stdout]
    provides [main] to pf

main : Task {} I32
main =
    request = {
        method: Get,
        headers: [],
        url: "http://www.example.com",
        mimeType: "",
        body: [],
        timeout: TimeoutMilliseconds 5000,
    }

    output <-
        Http.send request
        |> Task.await \resp -> resp |> Http.handleStringResponse |> Task.fromResult
        |> Task.onErr \err -> crash (Http.errorToString err)
        |> Task.await

    Stdout.line output
