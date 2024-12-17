app [main!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Stdout

# Basic HTTP GET request

main! = \_args ->

    response = try Http.send! {
        method: Get,
        headers: [],
        url: "http://www.example.com",
        mimeType: "",
        body: [],
        timeout: TimeoutMilliseconds 5000,
    }

    body = try Http.handleStringResponse response

    Stdout.line! "Response body:\n\t$(body)."
