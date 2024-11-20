app [main] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.11.0/z45Wzc-J39TLNweQUoLw3IGZtkQiEN3lTBv3BXErRjQ.tar.br",
}

import pf.Http
import pf.Stdout
import json.Json

# HTTP GET request with easy decoding to json

main : Task {} [Exit I32 Str]
main =
    run
    |> Task.mapErr (\err -> Exit 1 (Inspect.toStr err))

run : Task {} _
run =
    # Easy decoding/deserialization of { "foo": "something" } into a Roc var
    { foo } = Http.get! "http://localhost:8000" Json.utf8
    Stdout.line! "The json I received was: { foo: \"$(foo)\" }"
