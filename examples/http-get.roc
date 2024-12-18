app [main!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Stdout

# Basic HTTP GET request

main! = \_args ->

    response = Http.send! {
        method: Get,
        headers: [],
        uri: "http://www.example.com",
        body: [],
        timeout_ms: TimeoutMilliseconds 5000,
    }

    body = (Str.fromUtf8 response.body)?

    Stdout.line! "Response body:\n\t$(body)."
