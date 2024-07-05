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

SqlVal : [
    Null,
    Real F64,
    Integer I64,
    String Str,
    Bytes (List U8),
]

Stmt := {db: U64, stmt: U64}

prepareStmt : Ffi.Lib, Db, Str -> Task Stmt _
prepareStmt = \lib, @Db db, stmtStr ->
    Ffi.call lib "prepare_stmt" (db, stmtStr)
    |> Task.map \stmt -> @Stmt {db, stmt}

finalizeStmt : Ffi.Lib, Stmt -> Task {} _
finalizeStmt = \lib, @Stmt {db, stmt} ->
    Ffi.callNoReturn! lib "finalize_stmt" (db, stmt)

executeStmt : Ffi.Lib, Stmt, Dict Str SqlVal -> Task (List (List SqlVal)) _
executeStmt = \lib, @Stmt {db, stmt}, bindings ->
    Ffi.call lib "execute_stmt" (db, stmt, Dict.toList bindings)


main =
    Ffi.withLib "examples/ffi/sqlite.module" \lib ->
        path = "examples/ffi/todos.db"
        Stdout.line! "Opening db: $(path)"
        db = openDb! lib path

        stmtStr = "SELECT id, task FROM todos WHERE status = :status"
        Stdout.line! "Preparing statement: $(stmtStr)"
        stmt = prepareStmt! lib db stmtStr

        bindings = Dict.single ":status" (String "completed")
        res = executeStmt! lib stmt bindings

        res
        |> Inspect.toStr
        |> Stdout.line!

        Stdout.line! "Cleaning up"
        finalizeStmt! lib stmt
        closeDb! lib db
        Stdout.line! "Done"
