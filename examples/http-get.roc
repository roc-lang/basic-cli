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
        body: Http.emptyBody,
        timeout: TimeoutMilliseconds 5000,
    }

    output <- Http.send request
        |> Task.onErr \err -> err 
            |> Http.errorToString 
            |> Task.ok
        |> Task.await

    Stdout.line output
