app [main] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Task exposing [Task]
import pf.Stdout
import pf.Stderr

# Basic HTTP GET request

main =
    request = {
        method: Get,
        headers: [],
        url: "http://www.example.com",
        mimeType: "",
        body: [],
        timeout: TimeoutMilliseconds 5000,
    }

    sendResult =
        Http.send request
            |> Task.result!

    processedSendResult =
        Result.try sendResult Http.handleStringResponse

    when processedSendResult is
        Ok body ->
            Stdout.line "Response body:\n\t$(body)."

        Err err ->
            Stderr.line (Inspect.toStr err)
