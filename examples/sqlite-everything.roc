## Shows SQLite queries, decoders, nullable values, transactions, and errors.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Env
import pf.Stdout
import pf.Sqlite
import pf.Sqlite.Decoder
import pf.Sqlite.Query
import pf.Path

# Sql that was used to create the table:
# CREATE TABLE todos (
#     id INTEGER PRIMARY KEY AUTOINCREMENT,
#     task TEXT NOT NULL,
#     status TEXT NOT NULL,
#     edited BOOLEAN
# );
# Note 1: the edited column is nullable, this is for demonstration purposes only.
# We recommend using `NOT NULL` when possible.
# Note 2: boolean is "fake" in sqlite https://www.sqlite.org/datatype3.html

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Read from environment variable, or use default
	db_path = match Env.var!("DB_PATH") {
		Ok(p) => Path.from_os_str(p)
		Err(_) => "./examples/todos2.db"
	}

	# `{}` takes the defaults: create the file if it is missing, and wait up to
	# five seconds when another connection holds a lock.
	db = Sqlite.open!(db_path, {}) ? |err| OpenDatabaseFailed(err)

	# Example: print all rows
	all_todos = db.query_all!("SELECT * FROM todos", decode_full_todo) ? |err| QueryAllTodosFailed(err)

	Stdout.line!("All Todos:")?
	for t in all_todos {
		Stdout.line!("    id: ${t.id.to_str()}, task: ${t.task}, status: ${status_to_str(t.status)}, edited: ${edited_to_str(t.edited)}")?
	}

	# Example: filter rows by status (decode a single column)
	#
	# Each `${…}` in a query is a `Sqlite.Value`, sent to SQLite as the value of
	# a parameter. It is never pasted into the SQL text, so it needs no quoting
	# and cannot be misread as SQL.
	tasks_in_progress = db.query_all!(
		"SELECT task FROM todos WHERE status = ${encode_status(InProgress)}",
		Decoder.str("task"),
	) ? |err| QueryInProgressTasksFailed(err)

	Stdout.line!("")?
	Stdout.line!("In-progress Todos:")?
	for task in tasks_in_progress {
		Stdout.line!("    In-progress task: ${task}")?
	}

	# Example: insert a row
	example_task = "Make sql example."
	db.execute!(
		"INSERT INTO todos (task, status, edited) VALUES (${String(example_task)}, ${encode_status(InProgress)}, ${encode_edited(NotEdited)})",
	) ? |err| InsertTodoFailed(err)

	# Example: insert multiple rows from a Roc list
	#
	# The transaction makes the inserts one change: all of them are kept, or,
	# if the body returns an error, none. The statement is prepared once, the
	# first time through the loop.
	todos_list = [
		{ task: "Insert Roc list 1", status: Todo, edited: NotEdited },
		{ task: "Insert Roc list 2", status: Todo, edited: NotEdited },
		{ task: "Insert Roc list 3", status: Todo, edited: Unknown },
	]

	db.transaction!(
		|| {
			for todo in todos_list {
				db.execute!("INSERT INTO todos (task, status, edited) VALUES (${String(todo.task)}, ${encode_status(todo.status)}, ${encode_edited(todo.edited)})")?
			}
			Ok({})
		},
	) ? |err| InsertTodoListFailed(err)

	# Example: update a row
	db.execute!(
		"UPDATE todos SET status = ${encode_status(Completed)} WHERE task = ${String(example_task)}",
	) ? |err| UpdateTodoFailed(err)

	# Example: delete a row
	db.execute!("DELETE FROM todos WHERE task = ${String(example_task)}") ? |err| DeleteTodoFailed(err)

	# Example: read rows one at a time, and stop early
	#
	# `rows` runs the query as the loop asks for rows, so a large table is
	# never held in memory, and leaving the loop ends the query.
	Stdout.line!("")?
	Stdout.line!("Todos until the first inserted one:")?
	for! item in db.rows("SELECT * FROM todos ORDER BY id", decode_full_todo) {
		match item {
			Ok(t) if t.id > 3 => break
			Ok(t) => Stdout.line!("    task: ${t.task}")?
			# This row's values did not decode; go on with the next row.
			Err(BadRow(_)) => {}
			Err(Interrupted) => {
				return Err(Interrupted)
			}
			Err(SqliteErr(err)) => {
				return Err(ReadTodosFailed(SqliteErr(err)))
			}
			Err(Closed) => {
				return Err(ReadTodosFailed(Closed))
			}
		}
	}

	# Example: a query assembled at run time
	#
	# `Query.new` takes SQL text with `?` markers and their values in order.
	wanted_ids = [1, 3]
	markers = Str.join_with(wanted_ids.map(|_| "?"), ", ")
	wanted = db.query_all!(
		Query.new("SELECT task, status FROM todos WHERE id IN (${markers}) ORDER BY id", wanted_ids.map(|id| Integer(id))),
		decode_task_status,
	) ? |err| QueryWantedTodosFailed(err)

	Stdout.line!("")?
	Stdout.line!("Todos 1 and 3:")?
	for t in wanted {
		Stdout.line!("    task: ${t.task}, status: ${status_to_str(t.status)}")?
	}

	# Example: tell a constraint violation from other failures
	#
	# The table is temporary: it lives in this connection, not in the file.
	db.execute!("CREATE TEMP TABLE labels (name TEXT NOT NULL UNIQUE)") ? |err| CreateLabelsFailed(err)
	first = add_label!(db, "urgent") ? |err| AddLabelFailed(err)
	second = add_label!(db, "urgent") ? |err| AddLabelFailed(err)

	Stdout.line!("")?
	Stdout.line!("Adding the label \"urgent\" twice: ${Str.inspect(first)}, then ${Str.inspect(second)}")?

	# Example: delete all rows where ID is greater than 3 (cleanup so this example is repeatable)
	db.execute!("DELETE FROM todos WHERE id > ${Integer(3)}") ? |err| CleanupInsertedTodosFailed(err)

	# Example: count the number of rows
	#
	# SQLite integers are `I64`; `map_try` converts to another type, and its
	# error fails the row like any other decoding error.
	# TODO(roc-lang/roc#12264): drop the `map_err` once a builtin's one-tag
	# error keeps its tag when it joins the decoder's other errors.
	count = db.query_one!(
		"SELECT COUNT(*) AS count FROM todos",
		Decoder.i64("count").map_try(|n| n.to_u64_try().map_err(|OutOfRange| OutOfRange)),
	) ? |err| CountTodosFailed(err)

	Stdout.line!("")?
	Stdout.line!("Row count: ${count.to_str()}")?

	# Example: run the same query twice
	#
	# The connection keeps the statements it has prepared, so the second call
	# does not prepare the SQL again. The rows are read again each time.
	sorted_query = "SELECT * FROM todos ORDER BY LENGTH(task)"
	todos_sorted = db.query_all!(sorted_query, decode_task_status) ? |err| QuerySortedTodosFailed(err)
	todos_sorted_again = db.query_all!(sorted_query, decode_task_status) ? |err| QuerySortedTodosFailed(err)
	expect todos_sorted_again.len() == todos_sorted.len()

	Stdout.line!("")?
	Stdout.line!("Todos sorted by length of task description:")?
	for t in todos_sorted {
		Stdout.line!("    task: ${t.task}, status: ${status_to_str(t.status)}")?
	}

	# The connection would also be closed when `db` is no longer used;
	# `close!` does it now, and reports a failure.
	db.close!() ? |err| CloseDatabaseFailed(err)

	Ok({})
}

# Insert a label, reporting a duplicate as a value rather than an error.
add_label! : Sqlite.Db, Str => Try([Added, AlreadyExists], _)
add_label! = |db, name|
	match db.execute!("INSERT INTO labels (name) VALUES (${String(name)})") {
		Ok({}) => Ok(Added)
		Err(SqliteErr(Failed({ code: Constraint(Unique), .. }))) => Ok(AlreadyExists)
		Err(other) => Err(other)
	}

FullTodo : { id : I64, task : Str, status : TodoStatus, edited : EditedValue }

# Decode every column of the todos table.
#
# A decoder for a record is a record of decoders with the suffix `.Decoder`.
# `nullable` turns a decoder into one that accepts NULL, as `Err(Null)`.
decode_full_todo : Decoder(FullTodo, _)
decode_full_todo = {
	id: Decoder.i64("id"),
	task: Decoder.str("task"),
	status: Decoder.str("status").map_try(decode_status),
	edited: Decoder.bool("edited").nullable().map(decode_edited),
}.Decoder

# Decode just the task and status columns, leaving the status as text. With
# only the leaf decoders, the error type is `Sqlite.DecodeErr`.
decode_task_text : Decoder({ task : Str, status : Str }, Sqlite.DecodeErr)
decode_task_text = { task: Decoder.str("task"), status: Decoder.str("status") }.Decoder

# The same columns with the status parsed, built from the decoder above.
decode_task_status : Decoder({ task : Str, status : TodoStatus }, _)
decode_task_status = decode_task_text.map_try(
	|{ task, status }|
		match decode_status(status) {
			Ok(parsed) => Ok({ task, status: parsed })
			Err(UnknownStatus(text)) => Err(UnknownStatus(text))
		},
)

TodoStatus : [Todo, Completed, InProgress]

decode_status : Str -> Try(TodoStatus, [UnknownStatus(Str)])
decode_status = |status_str|
	match status_str {
		"todo" => Ok(Todo)
		"completed" => Ok(Completed)
		"in-progress" => Ok(InProgress)
		_ => Err(UnknownStatus(status_str))
	}

status_to_str : TodoStatus -> Str
status_to_str = |status|
	match status {
		Todo => "todo"
		Completed => "completed"
		InProgress => "in-progress"
	}

encode_status : TodoStatus -> Sqlite.Value
encode_status = |status| String(status_to_str(status))

EditedValue : [Edited, NotEdited, Unknown]

decode_edited : Try(Bool, [Null]) -> EditedValue
decode_edited = |edited|
	match edited {
		Ok(True) => Edited
		Ok(False) => NotEdited
		Err(Null) => Unknown
	}

edited_to_str : EditedValue -> Str
edited_to_str = |edited|
	match edited {
		Edited => "edited"
		NotEdited => "not-edited"
		Unknown => "unknown"
	}

encode_edited : EditedValue -> Sqlite.Value
encode_edited = |edited|
	match edited {
		Edited => Integer(1)
		NotEdited => Integer(0)
		Unknown => Null
	}
