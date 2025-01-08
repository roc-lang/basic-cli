app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Stdout
import pf.Sqlite

# To run this example: check the README.md in this folder

main! = \_args ->
    db_path = try Env.var! "DB_PATH"

    query_todos_by_status! = try Sqlite.prepare_query_many! {
        path: db_path,
        query: "SELECT id, task FROM todos WHERE status = :status;",
        bindings: \status -> [{ name: ":status", value: String status }],
        rows: { Sqlite.decode_record <-
            id: Sqlite.i64 "id" |> Sqlite.map_value Num.toStr,
            task: Sqlite.str "task",
        },
    }
    todo = try query_todos_by_status! "todo"

    try Stdout.line! "Todo Tasks:"
    try List.forEachTry! todo \{ id, task } ->
        Stdout.line! "\tid: $(id), task: $(task)"

    completed = try query_todos_by_status! "completed"

    try Stdout.line! "\nCompleted Tasks:"
    try List.forEachTry! completed \{ id, task } ->
        Stdout.line! "\tid: $(id), task: $(task)"

    Ok {}

