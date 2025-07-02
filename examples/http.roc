app [main!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import pf.Http
import pf.Stdout
import json.Json
import pf.Arg exposing [Arg]

# Demo of all basic-cli Http functions

# To run this example: 
# ```
# nix develop
# cd basic-cli/ci/rust_http_server
# cargo run
# ```
# Then in another terminal: follow the steps in the README.md file of this folder.

main! : List Arg => Result {} _
main! = |_args|

    # # HTTP GET a String
    #   ----------------

    hello_str : Str
    hello_str = Http.get_utf8!("http://localhost:8000/utf8test")?
    # If you want to see an example of the server side, see basic-cli/ci/rust_http_server/src/main.rs

    Stdout.line!("I received '${hello_str}' from the server.\n")?

    # # Getting json
    #   ------------

    # We decode/deserialize the json `{ "foo": "something" }` into a Roc record

    { foo } = Http.get!("http://localhost:8000", Json.utf8)?
    # If you want to see an example of the server side, see basic-cli/ci/rust_http_server/src/main.rs

    Stdout.line!("The json I received was: { foo: \"$(foo)\" }\n")?

    # # Getting a Response record
    #   -------------------------

    response : Http.Response
    response = Http.send!(
        {
            method: GET,
            headers: [],
            uri: "https://www.example.com",
            body: [],
            timeout_ms: TimeoutMilliseconds(5000),
        },
    )?

    body_str = (Str.from_utf8(response.body))?

    Stdout.line!("Response body:\n\t${body_str}.\n")?

    # # Using default_request and providing a header
    #   --------------------------------------------
    
    response_2 =
        Http.default_request
        |> &uri "https://www.example.com"
        |> &headers [Http.header(("Accept", "text/html"))]
        |> Http.send!()?

    body_str_2 = (Str.from_utf8(response_2.body))?

    # Same as above
    Stdout.line!("Response body 2:\n\t${body_str_2}.\n")
