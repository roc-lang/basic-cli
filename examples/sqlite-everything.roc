## Shows SQLite queries, decoders, nullable values, and prepared writes.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

import pf.OsStr
import pf.Env
import pf.Stdout
import pf.Sqlite
import pf.Path

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

main! : List(OsStr) => Try({}, _)
main! = |_args| run!()

run! : () => Try({}, _)
run! = || {

	# Read from environment variable, or use default
	db_path = match Env.var!("DB_PATH") {
		Ok(p) => Path.from_os_str(p)
		Err(_) => "./examples/todos2.db"
	}

	# Example: print all rows
	all_todos = Sqlite.query_many!({
		path: db_path,
		query: "SELECT * FROM todos;",
		bindings: [],
		rows: decode_full_todo,
	}) ? |err| QueryAllTodosFailed(err)

	print_line!("All Todos:")?
	for t in all_todos {
		print_line!("    id: ${I64.to_str(t.id)}, task: ${t.task}, status: ${status_to_str(t.status)}, edited: ${edited_to_str(decode_edited(t.edited_val))}")?
	}

	# Example: filter rows by status (decode a single column)
	tasks_in_progress = Sqlite.query_many!({
		path: db_path,
		query: "SELECT id, task, status FROM todos WHERE status = :status;",
		bindings: [{ name: ":status", value: encode_status(InProgress) }],
		rows: Sqlite.str("task"),
	}) ? |err| QueryInProgressTasksFailed(err)

	print_line!("")?
	print_line!("In-progress Todos:")?
	for task in tasks_in_progress {
		print_line!("    In-progress task: ${task}")?
	}

	# Example: insert a row
	Sqlite.execute!({
		path: db_path,
		query: "INSERT INTO todos (task, status, edited) VALUES (:task, :status, :edited);",
		bindings: [
			{ name: ":task", value: String("Make sql example.") },
			{ name: ":status", value: encode_status(InProgress) },
			{ name: ":edited", value: encode_edited(NotEdited) },
		],
	}) ? |err| InsertTodoFailed(err)

	# Example: insert multiple rows from a Roc list
	todos_list = [
		{ task: "Insert Roc list 1", status: Todo, edited: NotEdited },
		{ task: "Insert Roc list 2", status: Todo, edited: NotEdited },
		{ task: "Insert Roc list 3", status: Todo, edited: NotEdited },
	]

	values_str = Str.join_with(
		todos_list.map_with_index(
			|_t, indx| {
				i = U64.to_str(indx)
				"(:task${i}, :status${i}, :edited${i})"
			},
		),
		", ",
	)

	# Bindings map each named placeholder (like :task0) in the query to its actual
	# value. Passing values this way lets SQLite handle escaping and type conversion,
	# which avoids SQL injection and quoting bugs from building the query as a string.
	binding_groups = List.map_with_index(
		todos_list,
		|t, indx| {
			i = U64.to_str(indx)
			[
				{ name: ":task${i}", value: String(t.task) },
				{ name: ":status${i}", value: encode_status(t.status) },
				{ name: ":edited${i}", value: encode_edited(t.edited) },
			]
		},
	)

	all_bindings = Iter.fold(List.iter(binding_groups), [], |acc, group| List.concat(acc, group))

	Sqlite.execute!({
		path: db_path,
		query: "INSERT INTO todos (task, status, edited) VALUES ${values_str};",
		bindings: all_bindings,
	}) ? |err| InsertTodoListFailed(err)

	# Example: update a row
	Sqlite.execute!({
		path: db_path,
		query: "UPDATE todos SET status = :status WHERE task = :task;",
		bindings: [
			{ name: ":task", value: String("Make sql example.") },
			{ name: ":status", value: encode_status(Completed) },
		],
	}) ? |err| UpdateTodoFailed(err)

	# Example: delete a row
	Sqlite.execute!({
		path: db_path,
		query: "DELETE FROM todos WHERE task = :task;",
		bindings: [{ name: ":task", value: String("Make sql example.") }],
	}) ? |err| DeleteTodoFailed(err)

	# Example: delete all rows where ID is greater than 3 (cleanup so this example is repeatable)
	Sqlite.execute!({
		path: db_path,
		query: "DELETE FROM todos WHERE id > :id;",
		bindings: [{ name: ":id", value: Integer(3) }],
	}) ? |err| CleanupInsertedTodosFailed(err)

	# Example: count the number of rows
	count = Sqlite.query!({
		path: db_path,
		query: "SELECT COUNT(*) as \"count\" FROM todos;",
		bindings: [],
		row: Sqlite.u64("count"),
	}) ? |err| CountTodosFailed(err)

	print_line!("")?
	print_line!("Row count: ${U64.to_str(count)}")?

	# Example: prepared statements
	# Note: This is faster if you execute the same prepared statement many times.
	prepared_update = Sqlite.prepare!({
		path: db_path,
		query: "UPDATE todos SET status = status WHERE id = :id;",
	}) ? |err| PrepareUpdateTodoFailed(err)

	prepared_update.execute!([{ name: ":id", value: Integer(1) }]) ? |err| ExecutePreparedUpdateFailed(err)
	# You can run the same prepared statement again with different values.
	# Each execution starts fresh, so the previous run's values don't carry over.
	prepared_update.execute!([{ name: ":id", value: Integer(2) }]) ? |err| ReusePreparedUpdateFailed(err)

	prepared_count = Sqlite.prepare!({
		path: db_path,
		query: "SELECT COUNT(*) as \"count\" FROM todos;",
	}) ? |err| PrepareCountTodosFailed(err)
	prepared_count_value = prepared_count.query!([], Sqlite.u64("count")) ? |err| QueryPreparedCountFailed(err)
	expect prepared_count_value == count

	prepared_query = Sqlite.prepare!({
		path: db_path,
		# sort by the length of the task description
		query: "SELECT * FROM todos ORDER BY LENGTH(task);",
	}) ? |err| PrepareSortedTodosFailed(err)

	todos_sorted = prepared_query.query_many!([], decode_task_status) ? |err| QuerySortedTodosFailed(err)
	# Note that the result is not cached if we run the same prepared query again.
	todos_sorted_again = prepared_query.query_many!([], decode_task_status) ? |err| ReuseSortedTodosFailed(err)
	expect todos_sorted_again.len() == todos_sorted.len()

	print_line!("")?
	print_line!("Todos sorted by length of task description:")?
	for t in todos_sorted {
		print_line!("    task: ${t.task}, status: ${status_to_str(t.status)}")?
	}

	Ok({})
}

print_line! : Str => Try({}, _)
print_line! = |s| Stdout.line!(s)

# Decode every column of the todos table. The nullable `edited` column is returned
# raw (`[NotNull(I64), Null]`) and interpreted by `decode_edited` at the call site:
# decoding both `status` (via `?`) and `edited` inside this nested decoder lambda
# currently panics the type checker, so we keep only one interpreting `?` here.
decode_full_todo = |cols|
	|stmt| {
		id = Sqlite.i64("id")(cols)(stmt)?
		task = Sqlite.str("task")(cols)(stmt)?
		status_str = Sqlite.str("status")(cols)(stmt)?
		match decode_status(status_str) {
			Ok(status) => {
				edited_val = Sqlite.nullable_i64("edited")(cols)(stmt)?
				Ok({ id, task, status, edited_val })
			}
			Err(ParseError(message)) => Err(ParseError(message))
		}
	}

# Decode just the task and status columns.
decode_task_status = |cols|
	|stmt| {
		task = Sqlite.str("task")(cols)(stmt)?
		status_str = Sqlite.str("status")(cols)(stmt)?
		match decode_status(status_str) {
			Ok(status) => Ok({ task, status })
			Err(ParseError(message)) => Err(ParseError(message))
		}
	}

TodoStatus : [Todo, Completed, InProgress]

decode_status = |status_str|
	match status_str {
		"todo" => Ok(Todo)
		"completed" => Ok(Completed)
		"in-progress" => Ok(InProgress)
		_ => Err(ParseError("Unknown status str: ${status_str}"))
	}

status_to_str : TodoStatus -> Str
status_to_str = |status|
	match status {
		Todo => "todo"
		Completed => "completed"
		InProgress => "in-progress"
	}

encode_status = |status| String(status_to_str(status))

EditedValue : [Edited, NotEdited, Unknown]

decode_edited = |edited_val|
	match edited_val {
		NotNull(1) => Edited
		NotNull(0) => NotEdited
		_ => Unknown
	}

edited_to_str : EditedValue -> Str
edited_to_str = |edited|
	match edited {
		Edited => "edited"
		NotEdited => "not-edited"
		Unknown => "unknown"
	}

encode_edited = |edited|
	match edited {
		Edited => Integer(1)
		NotEdited => Integer(0)
		Unknown => Null
	}
