app "http-get"
    packages { pf: "../platform/main.roc" }
    imports [pf.Http, pf.Task.{ Task }, pf.Stdout]
    provides [main] to pf

main =
    request = {
        method: Get,
        headers: [],
        url: "http://www.example.com",
        mimeType: "",
        body: [],
        timeout: TimeoutMilliseconds 5000,
    }

    resp = Http.send! request

    output = when resp |> Http.handleStringResponse is 
        Err err -> crash (Http.errorToString err)
        Ok body -> body

    Stdout.line output
