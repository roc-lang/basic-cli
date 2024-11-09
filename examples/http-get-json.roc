app [main!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.10.1/jozYCvOqoYa-cV6OdTcxw3uDGn61cLvzr5dK1iKf1ag.tar.br",
}

import pf.Http
import pf.Stdout
import json.Json

# HTTP GET request with easy decoding to json
main! = \{} ->

    # Easy decoding/deserialization of { "foo": "something" } into a Roc var
    { foo } = try Http.get! "http://localhost:8000" Json.utf8

    Stdout.line! "The json I received was: { foo: \"$(foo)\" }"
