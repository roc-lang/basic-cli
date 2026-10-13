## Query a SQLite database and decode rows into records.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Env
import pf.Stdout
import pf.Sqlite
import pf.Sqlite.Decoder
import pf.Path

# Sql to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL
# );

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	db_path = match Env.var!("DB_PATH") {
		Ok(p) => Path.from_os_str(p)
		Err(_) => "./examples/todos.db"
	}

	# This example only reads, so it opens the file read-only.
	db = Sqlite.open!(db_path, { mode: ReadOnly }) ? |err| OpenDatabaseFailed(err)

	# `query_one!` when you expect exactly one row. A column is named by its
	# name, or by its position: `0` is the first.
	count = db.query_one!("SELECT COUNT(*) FROM todos", Decoder.i64(0)) ? |err| CountTodosFailed(err)
	Stdout.line!("There are ${count.to_str()} todos.")?

	todos = query_todos_by_status!(db, Todo) ? |err| QueryTodosFailed(err)

	Stdout.line!("")?
	Stdout.line!("Todos still to do:")?
	for todo in todos {
		print_todo!(todo)?
	}

	completed_todos = query_todos_by_status!(db, Completed) ? |err| QueryCompletedTodosFailed(err)

	Stdout.line!("")?
	Stdout.line!("Completed Todos:")?
	for todo in completed_todos {
		print_todo!(todo)?
	}

	Ok({})
}

Todo : { id : I64, status : TodoStatus, task : Str }

TodoStatus : [Todo, Completed, InProgress]

print_todo! : Todo => Try({}, _)
print_todo! = |todo|
	Stdout.line!("    id: ${todo.id.to_str()}, task: ${todo.task}, status: ${status_to_str(todo.status)}")

# `query_all!` when you expect any number of rows.
#
# The `${…}` is not pasted into the SQL: it is sent to SQLite as the value of
# a parameter, so it needs no quoting or escaping.
query_todos_by_status! : Sqlite.Db, TodoStatus => Try(List(Todo), _)
query_todos_by_status! = |db, status|
	db.query_all!("SELECT id, task, status FROM todos WHERE status = ${String(status_to_sql(status))}", decode_todo)

# A row decoder is a record of column decoders, turned into a decoder of
# records by the record-builder suffix `.Decoder`.
#
# The second type argument is what can be wrong with a row. It is inferred
# here: `Sqlite.DecodeErr` for the columns, and `UnknownStatus` from
# `status_from_sql`. A row that fails to decode is reported as `BadRow(err)`.
decode_todo : Decoder(Todo, _)
decode_todo = {
	id: Decoder.i64("id"),
	task: Decoder.str("task"),
	status: Decoder.str("status").map_try(status_from_sql),
}.Decoder

status_to_str : TodoStatus -> Str
status_to_str = |status|
	match status {
		Todo => "Todo"
		Completed => "Completed"
		InProgress => "InProgress"
	}

status_to_sql : TodoStatus -> Str
status_to_sql = |status|
	match status {
		Todo => "todo"
		Completed => "completed"
		InProgress => "in-progress"
	}

status_from_sql : Str -> Try(TodoStatus, [UnknownStatus(Str)])
status_from_sql = |status_str|
	match status_str {
		"todo" => Ok(Todo)
		"completed" => Ok(Completed)
		"in-progress" => Ok(InProgress)
		_ => Err(UnknownStatus(status_str))
	}
