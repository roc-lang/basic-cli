app [main] { 
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.8.0/BlWJJh_ouV7c_IwvecYpgpR3jOCzVO-oyk-7ISdl2S4.tar.br"
}

import json.Core exposing [json]

import pf.Stdout
import pf.Task exposing [Task]

bytes = Encode.toBytes "abc" json

main =
    dbg bytes
    Stdout.line "Hello, World!"
