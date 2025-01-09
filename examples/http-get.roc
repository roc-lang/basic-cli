app [main!] { pf: platform "../platform/main.roc" }

import pf.Http
import pf.Stdout

# Basic HTTP GET request
# To run this example: check the README.md in this folder

main! = \_args ->

    response = Http.send!(
        {
            method: GET,
            headers: [],
            uri: "http://www.example.com",
            body: [],
            timeout_ms: TimeoutMilliseconds(5000),
        },
    )

    body = (Str.from_utf8(response.body))?

    Stdout.line!("Response body:\n\t$(body).")
