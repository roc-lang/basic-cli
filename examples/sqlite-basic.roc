app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Stdout
import pf.Sqlite
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder and set `export DB_PATH=./examples/todos.db`

# Demo of basic Sqlite usage

# Sql to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL
# );

main! : List Arg => Result {} _
main! = |_args|
    db_path = Env.var!("DB_PATH")?

    todos = query_todos_by_status!(db_path, "todo")?

    Stdout.line!("All Todos:")?

    # print todos
    List.for_each_try!(
        todos,
        |{ id, task, status }|
            Stdout.line!("\tid: ${id}, task: ${task}, status: ${Inspect.to_str(status)}"),
    )?

    completed_todos = query_todos_by_status!(db_path, "completed")?

    Stdout.line!("\nCompleted Todos:")?
    List.for_each_try!(
        completed_todos,
        |{ id, task, status }|
            Stdout.line!("\tid: ${id}, task: ${task}, status: ${Inspect.to_str(status)}"),
    )


Todo : { id : Str, status : TodoStatus, task : Str }

query_todos_by_status! : Str, Str => Result (List Todo) (Sqlite.SqlDecodeErr _)
query_todos_by_status! = |db_path, status|
    Sqlite.query_many!(
        {
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE status = :status;",
            bindings: [{ name: ":status", value: String(status) }],
            # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
            rows: { Sqlite.decode_record <-
                id: Sqlite.i64("id") |> Sqlite.map_value(Num.to_str),
                task: Sqlite.str("task"),
                status: Sqlite.str("status") |> Sqlite.map_value_result(decode_todo_status),
            },
        },
    )

TodoStatus : [Todo, Completed, InProgress]

decode_todo_status : Str -> Result TodoStatus _
decode_todo_status = |status_str|
    when status_str is
        "todo" -> Ok(Todo)
        "completed" -> Ok(Completed)
        "in-progress" -> Ok(InProgress)
        _ -> Err(ParseError("Unknown status str: ${status_str}"))