app [main] { pf: platform "../../platform/main.roc" }

import pf.Ffi
import pf.Stdout
import pf.Task exposing [Task]

Db := U64

openDb : Ffi.Lib, Str -> Task Db _
openDb = \lib, path ->
    Ffi.call lib "open_db" path
    |> Task.map @Db

closeDb : Ffi.Lib, Db -> Task {} _
closeDb = \lib, @Db db ->
    Ffi.callNoReturn! lib "close_db" db

main =
    Ffi.withLib "examples/ffi/sqlite.module" \lib ->
        Stdout.line! "Loaded Successfully!!!"

        path = "examples/ffi/todos.db"
        Stdout.line! "Opening db: $(path)"

        db = openDb! lib path
        Stdout.line! "Oh wow, it didn't crash"
        closeDb! lib db
