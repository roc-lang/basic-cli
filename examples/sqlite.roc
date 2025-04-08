app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Stdout
import pf.Sqlite

# To run this example: check the README.md in this folder

main! = |_args|
    db_path = Env.var!("DB_PATH")?

    todo = query_todos_by_status!(db_path, "todo")?

    Stdout.line!("Todo Tasks:")?

    List.for_each_try!(
        todo,
        |{ id, task, status }|
            Stdout.line!("\tid: ${id}, task: ${task}, status: ${Inspect.to_str(status)}"),
    )?

    completed = query_todos_by_status!(db_path, "completed")?

    Stdout.line!("\nCompleted Tasks:")?

    List.for_each_try!(
        completed,
        |{ id, task, status }|
            Stdout.line!("\tid: ${id}, task: ${task}, status: ${Inspect.to_str(status)}"),
    )?

    Ok({})

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
                status: Sqlite.str("status") |> Sqlite.map_value_result(decode_db_status),
            },
        },
    )

TodoStatus : [Todo, Completed, InProgress]

decode_db_status : Str -> Result TodoStatus _
decode_db_status = |status_str|
    when status_str is
        "todo" -> Ok(Todo)
        "completed" -> Ok(Completed)
        "in-progress" -> Ok(InProgress)
        _ -> Err(ParseError("Unknown status str: ${status_str}"))