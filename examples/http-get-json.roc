app [main!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.11.0/z45Wzc-J39TLNweQUoLw3IGZtkQiEN3lTBv3BXErRjQ.tar.br",
}

import pf.Http
import pf.Stdout
import json.Json

# HTTP GET request with easy decoding to json
main! = \_ ->

    # Easy decoding/deserialization of { "foo": "something" } into a Roc var
    { foo } = try Http.get! "http://localhost:8000" Json.utf8
    # If you want to see an example of the server side, see basic-cli/ci/rust_http_server/src/main.rs

    Stdout.line! "The json I received was: { foo: \"$(foo)\" }"
