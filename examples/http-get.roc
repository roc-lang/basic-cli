app "http-get"
    packages { pf: "../src/main.roc" }
    imports [pf.Http, pf.Task.{ Task }, pf.Stdin, pf.Stdout]
    provides [main] to pf

main : Task {} U32
main =
    _ <- Task.await (Stdout.line "Enter a URL to fetch. It must contain a scheme like \"http://\" or \"https://\".")

    url <- Task.await Stdin.line

    request = {
        method: Get,
        headers: [],
        url,
        body: Http.emptyBody,
        timeout: NoTimeout,
    }

    output <- Http.send request
        |> Task.onFail (\err -> err |> Http.errorToString |> Task.ok)
        |> Task.await

    Stdout.line output
