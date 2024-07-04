app [main] { pf: platform "../../platform/main.roc" }

import pf.Ffi
import pf.Stdout
import pf.Task exposing [Task]

main =
    Ffi.withLib "examples/ffi/sqlite.module" \lib ->
        Stdout.line! "Loaded Successfully!!!"

        path = "examples/ffi/todos.db"
        Stdout.line! "Opening db: \(path)"

        db : U64
        db = Ffi.call! lib "open_db" path

        Stdout.line! "Oh wow, it didn't crash"
        
        Ffi.callNoReturn! lib "close_db" db

