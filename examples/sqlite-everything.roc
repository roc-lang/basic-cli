app [main!] { pf: platform "../platform/main.roc" }

import pf.Env
import pf.Stdout
import pf.Sqlite
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder and set `export DB_PATH=./examples/todos2.db`

# Demo of basic Sqlite usage

# Sql that was used to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL,
#     edited BOOLEAN,
# );
# Note 1: the edited column is nullable, this is for demonstration purposes only.
# We recommend using `NOT NULL` when possible.
# Note 2: boolean is "fake" in sqlite https://www.sqlite.org/datatype3.html

main! : List Arg => Result {} _
main! = |_args|
    db_path = Env.var!("DB_PATH")?

    # Example: print all rows

    all_todos = Sqlite.query_many!({
        path: db_path,
        query: "SELECT * FROM todos;",
        bindings: [],
        # This uses the record builder syntax: https://www.roc-lang.org/examples/RecordBuilder/README.html
        rows: { Sqlite.decode_record <-
            id: Sqlite.i64("id"),
            task: Sqlite.str("task"),
            status: Sqlite.str("status") |> Sqlite.map_value_result(decode_status),
            # bools in sqlite are actually integers
            edited: Sqlite.nullable_i64("edited") |> Sqlite.map_value(decode_edited),
        },
    })?

    Stdout.line!("All Todos:")?

    List.for_each_try!(
        all_todos,
        |{ id, task, status, edited }|
            Stdout.line!("\tid: ${Num.to_str(id)}, task: ${task}, status: ${Inspect.to_str(status)}, edited: ${Inspect.to_str(edited)}"),
    )?

    # Example: filter rows by status

    tasks_in_progress = Sqlite.query_many!(
        {
            path: db_path,
            query: "SELECT id, task, status FROM todos WHERE status = :status;",
            bindings: [{ name: ":status", value: encode_status(InProgress) }],
            rows: Sqlite.str("task")
        },
    )?

    Stdout.line!("\nIn-progress Todos:")?

    List.for_each_try!(
        tasks_in_progress,
        |task_description|
            Stdout.line!("\tIn-progress tasks: ${task_description}"),
    )?

    # Example: insert a row

    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO todos (task, status, edited) VALUES (:task, :status, :edited);",
        bindings: [
            { name: ":task", value: String("Make sql example.") },
            { name: ":status", value: encode_status(InProgress) },
            { name: ":edited", value: encode_edited(NotEdited) },
        ],
    })?

    # Example: insert multiple rows from a Roc list

    todos_list : List ({task : Str, status : TodoStatus, edited : EditedValue})
    todos_list = [
        { task: "Insert Roc list 1", status: Todo, edited: NotEdited },
        { task: "Insert Roc list 2", status: Todo, edited: NotEdited },
        { task: "Insert Roc list 3", status: Todo, edited: NotEdited },
    ]

    values_str =
        todos_list
        |> List.map_with_index(
            |_, indx|
                indx_str = Num.to_str(indx)
                "(:task${indx_str}, :status${indx_str}, :edited${indx_str})",
        )
        |> Str.join_with(", ")

    all_bindings =
        todos_list
        |> List.map_with_index(
            |{ task, status, edited }, indx|
                indx_str = Num.to_str(indx)
                [
                    { name: ":task${indx_str}", value: String(task) },
                    { name: ":status${indx_str}", value: encode_status(status) },
                    { name: ":edited${indx_str}", value: encode_edited(edited) },
                ],
        )
        |> List.join

    Sqlite.execute!({
        path: db_path,
        query: "INSERT INTO todos (task, status, edited) VALUES ${values_str};",
        bindings: all_bindings,
    })?

    # Example: update a row

    Sqlite.execute!({
        path: db_path,
        query: "UPDATE todos SET status = :status WHERE task = :task;",
        bindings: [
            { name: ":task", value: String("Make sql example.") },
            { name: ":status", value: encode_status(Completed) },
        ],
    })?

    # Example: delete a row

    Sqlite.execute!({
        path: db_path,
        query: "DELETE FROM todos WHERE task = :task;",
        bindings: [
            { name: ":task", value: String("Make sql example.") },
        ],
    })?

    # Example: delete all rows where ID is greater than 3

    Sqlite.execute!({
        path: db_path,
        query: "DELETE FROM todos WHERE id > :id;",
        bindings: [
            { name: ":id", value: Integer(3) },
        ],
    })?

    # Example: count the number of rows

    count = Sqlite.query!({
        path: db_path,
        query: "SELECT COUNT(*) as \"count\" FROM todos;",
        bindings: [],
        row: Sqlite.u64("count"),
    })?

    expect count == 3

    # Example: prepared statements
    # Note: This leads to better performance if you are executing the same prepared statement multiple times.

    prepared_query = Sqlite.prepare!({
        path : db_path,
        query : "SELECT * FROM todos ORDER BY LENGTH(task);", # sort by the length of the task description
    })?
    
    todos_sorted = Sqlite.query_many_prepared!({
        stmt: prepared_query,
        bindings: [],
        rows: { Sqlite.decode_record <-
            task: Sqlite.str("task"),
            status: Sqlite.str("status") |> Sqlite.map_value_result(decode_status),
        },
    })?

    Stdout.line!("\nTodos sorted by length of task description:")?

    List.for_each_try!(
        todos_sorted,
        |{ task, status }|
            Stdout.line!("\t task: ${task}, status: ${Inspect.to_str(status)}"),
    )?

    Ok({})

TodoStatus : [Todo, Completed, InProgress]

decode_status : Str -> Result TodoStatus _
decode_status = |status_str|
    when status_str is
        "todo" -> Ok(Todo)
        "completed" -> Ok(Completed)
        "in-progress" -> Ok(InProgress)
        _ -> Err(ParseError("Unknown status str: ${status_str}"))

status_to_str : TodoStatus -> Str
status_to_str = |status|
    when status is
        Todo -> "todo"
        Completed -> "completed"
        InProgress -> "in-progress"

    
encode_status : TodoStatus -> [String Str]
encode_status = |status|
    String(status_to_str(status))

EditedValue : [Edited, NotEdited, Null]

decode_edited : [NotNull I64, Null] -> EditedValue
decode_edited = |edited_val|
    when edited_val is
        NotNull 1 -> Edited
        NotNull 0 -> NotEdited
        _ -> Null

encode_edited : EditedValue -> [Integer I64, Null]
encode_edited = |edited|
    when edited is
        Edited -> Integer(1)
        NotEdited -> Integer(0)
        Null -> Null
