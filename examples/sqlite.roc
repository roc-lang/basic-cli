app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Stdout
import pf.Sqlite

main! = \_args ->
    db_path = Env.var!? "DB_PATH"

    todo = query_todos_by_status!? db_path "todo"

    Stdout.line!? "Todo Tasks:"
    List.forEachTry!? todo \{ id, task } ->
        Stdout.line! "\tid: $(id), task: $(task)"

    completed = query_todos_by_status!? db_path "completed"

    Stdout.line!? "\nCompleted Tasks:"
    List.forEachTry!? completed \{ id, task } ->
        Stdout.line! "\tid: $(id), task: $(task)"

    Ok {}

query_todos_by_status! = \db_path, status ->
    Sqlite.query_many! {
        path: db_path,
        query: "SELECT id, task FROM todos WHERE status = :status;",
        bindings: [{ name: ":status", value: String status }],
        rows: { Sqlite.decode_record <-
            id: Sqlite.i64 "id" |> Sqlite.map_value Num.toStr,
            task: Sqlite.str "task",
        },
    }
