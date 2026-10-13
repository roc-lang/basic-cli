import Duration
import Host
import InternalSqlite
import Path
import Resource

## Open SQLite databases, run statements, and decode rows.
##
## A [Db] is one connection. A string literal is a [Query]: each `${…}` in it
## is a [Value] bound as a parameter, never pasted into the SQL text. A
## [Decoder] turns a result row into a Roc value.
##
## ```roc
## import pf.Sqlite
## import pf.Sqlite.Decoder
##
## decode_todo : Decoder({ id : I64, task : Str }, Sqlite.DecodeErr)
## decode_todo = { id: Decoder.i64("id"), task: Decoder.str("task") }.Decoder
##
## db = Sqlite.open!("app.db", {})?
## todo = db.query_one!("SELECT id, task FROM todos WHERE id = ${Integer(id)}", decode_todo)?
## ```
##
## Without the second import the same names are `Sqlite.Decoder.i64("id")` and
## `{ … }.Sqlite.Decoder`.
Sqlite :: [].{

	## A value bound to a parameter or read from a column.
	Value : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	## How to open a database; `{}` takes every default.
	##
	## `mode` is `ReadWriteCreate` (create the file if it is missing),
	## `ReadWrite` (the file must exist) or `ReadOnly` (the file must exist and
	## every write fails with `Failed({ code: ReadOnly, .. })`).
	##
	## `busy_timeout` is how long a statement waits for another connection's
	## lock before failing with `Failed({ code: Busy, .. })`. `Duration.zero`
	## fails at once.
	OpenOptions := {
		mode : [ReadWriteCreate, ReadWrite, ReadOnly] ?? ReadWriteCreate,
		busy_timeout : Duration ?? Duration.seconds(5),
	}

	## Open a connection to the database file at `path`.
	##
	## Every call opens a new connection, also for a path that is already
	## open. The path `":memory:"` opens a new, private in-memory database,
	## like [open_in_memory!].
	##
	## ```roc
	## db = Sqlite.open!("app.db", {})?
	## readonly = Sqlite.open!("app.db", { mode: ReadOnly })?
	## ```
	open! : Path, OpenOptions => Try(Db, [SqliteErr(Err)])
	open! = |path, options|
		match Host.sqlite_open!(Path.to_raw(path), options.mode, options.busy_timeout.to_nanos()) {
			Ok(host) => Ok(Db.{ host })
			Err(failure) => Err(SqliteErr(failed(failure)))
		}

	## Open a new, private in-memory database. It is discarded when the
	## connection is closed or released.
	open_in_memory! : () => Try(Db, [SqliteErr(Err)])
	open_in_memory! = || open!(":memory:", {})

	## A connection to one database.
	##
	## The connection is closed when the last reference to the `Db`, and to
	## every unfinished [Db.rows] stream made from it, is released. [close!]
	## closes it earlier and reports a failure to do so.
	##
	## The connection keeps the statements it has prepared, keyed by their SQL
	## text, so running the same text again does not prepare it again. It keeps
	## at most 32, dropping the least recently used.
	Db :: { host : Resource.SqliteDb }.{

		# A tag union that crosses the host boundary is closed by design, so
		# every method below rebuilds the error it forwards from the host. That
		# gives callers an open union, which `?` can combine with other error
		# types however the method is called.

		## Render the connection without exposing its host handle.
		to_inspect : Db -> Str
		to_inspect = |_| "Sqlite.Db(<opaque>)"

		## Close the connection now. An open transaction is rolled back, and
		## every unfinished [Db.rows] stream ends with `Err(Closed)`.
		##
		## After `close!`, every other method returns `Err(Closed)`. Closing a
		## closed connection is `Ok({})`.
		close! : Db => Try({}, [SqliteErr(Err)])
		close! = |db|
			match Host.sqlite_close!(db.host) {
				Ok({}) => Ok({})
				Err(failure) => Err(SqliteErr(failed(failure)))
			}

		## Run one statement that returns no rows, such as an `INSERT`,
		## `UPDATE`, `DELETE` or `CREATE TABLE`.
		##
		## A statement with result columns is rejected before it runs with
		## `ReturnsRows`, even if it would return no row; so an
		## `INSERT … RETURNING` inserts nothing. Text holding a second
		## statement is rejected with `MultipleStatements`; use
		## [execute_script!] for that. Text holding no statement at all, only
		## white space or comments, does nothing.
		##
		## ```roc
		## db.execute!("INSERT INTO todos (task) VALUES (${String(task)})")?
		## ```
		execute! : Db, Query => Try({}, [SqliteErr(Err), Closed])
		execute! = |db, query|
			match Host.sqlite_execute!(db.host, query.sql, query.params) {
				Ok({}) => Ok({})
				Err(problem) => Err(widen_problem(problem))
			}

		## Run every statement in `sql`, in order, stopping at the first one
		## that fails. The statements take no parameters, and any rows they
		## return are discarded.
		##
		## The statements are not wrapped in a transaction: those before a
		## failing one have taken effect, unless the text itself has a `BEGIN`
		## or the call is made inside [transaction!].
		##
		## ```roc
		## db.execute_script!(
		##     \\CREATE TABLE todos (id INTEGER PRIMARY KEY, task TEXT NOT NULL);
		##     \\CREATE INDEX todos_task ON todos (task);
		## )?
		## ```
		execute_script! : Db, Str => Try({}, [SqliteErr(Err), Closed])
		execute_script! = |db, sql|
			match Host.sqlite_execute_script!(db.host, sql) {
				Ok({}) => Ok({})
				Err(problem) => Err(widen_problem(problem))
			}

		## Run a query that returns exactly one row and decode it.
		##
		## No row is `Err(NoRows)` and a second row is `Err(TooManyRows)`. A row
		## whose values the decoder rejects is `Err(BadRow(err))`.
		##
		## ```roc
		## count = db.query_one!("SELECT COUNT(*) FROM todos", Decoder.i64(0))?
		## ```
		query_one! : Db, Query, Decoder(a, err) => Try(a, [SqliteErr(Err), Closed, NoRows, TooManyRows, BadRow(err)])
		query_one! = |db, query, decoder| {
			cursor = start!(db, query, decoder)?
			first = match next_cells!(cursor) {
				Ok(cells) => cells
				Err(Done) => {
					return Err(NoRows)
				}
				Err(Closed) => {
					return Err(Closed)
				}
				Err(SqliteErr(err)) => {
					return Err(SqliteErr(err))
				}
			}
			# The cells are a copy of the row, so the row can be decoded after the
			# step that looks for a second one.
			match next_cells!(cursor) {
				Ok(_) => Err(TooManyRows)
				Err(Done) =>
					match decode_cells(cursor, decoder, first) {
						Ok(value) => Ok(value)
						Err(err) => Err(BadRow(err))
					}
				Err(Closed) => Err(Closed)
				Err(SqliteErr(err)) => Err(SqliteErr(err))
			}
		}

		## Run a query and decode every row into a list.
		##
		## The first row whose values the decoder rejects ends the query with
		## `Err(BadRow(err))`; to skip such rows instead, use [Db.rows].
		##
		## ```roc
		## tasks = db.query_all!("SELECT task FROM todos ORDER BY id", Decoder.str("task"))?
		## ```
		query_all! : Db, Query, Decoder(a, err) => Try(List(a), [SqliteErr(Err), Closed, BadRow(err)])
		query_all! = |db, query, decoder| {
			cursor = start!(db, query, decoder)?
			var $values = []
			var $running = True
			while $running {
				match next_cells!(cursor) {
					Ok(cells) =>
						match decode_cells(cursor, decoder, cells) {
							Ok(value) => {
								$values = $values.append(value)
							}
							Err(err) => {
								return Err(BadRow(err))
							}
						}
					Err(Done) => {
						$running = False
					}
					Err(Closed) => {
						return Err(Closed)
					}
					Err(SqliteErr(err)) => {
						return Err(SqliteErr(err))
					}
				}
			}
			Ok($values)
		}

		## Lazily run a query, decoding one row for each item pulled.
		##
		## Building the stream does nothing; the first pull prepares the
		## statement, binds its parameters and resolves the decoder's columns.
		## The stream ends after the last row.
		##
		## A `BadRow(err)` item concerns one row, whose values the decoder
		## rejected, and the stream continues with the next row. A `SqliteErr`
		## or `Closed` item is the last one. A column the decoder names that
		## the query does not return is `Err(SqliteErr(ColumnNotFound(_)))`,
		## the only item.
		##
		## ```roc
		## for! item in db.rows("SELECT id, payload FROM events ORDER BY id", decode_event) {
		##     match item {
		##         Ok(event) if event.id > last => break
		##         Ok(event) => Stdout.line!(event.payload)?
		##         Err(BadRow(_)) => {}
		##         Err(SqliteErr(err)) => { return Err(SqliteErr(err)) }
		##         Err(Closed) => { return Err(Closed) }
		##     }
		## }
		## ```
		##
		## The stream holds its statement, and with it SQLite's read lock, until
		## it has finished or is released. The connection stays usable
		## meanwhile, also for another stream of the same query.
		##
		## A stream left with `break` is released when the function containing
		## the loop returns, not at the end of the loop
		## ([roc-lang/roc#12266](https://github.com/roc-lang/roc/issues/12266)).
		## Give the loop a function of its own if the lock has to be gone before
		## the next statement, such as a `DROP TABLE`.
		rows : Db, Query, Decoder(a, err) -> Stream(Try(a, [SqliteErr(Err), Closed, BadRow(err)]))
		rows = |db, query, decoder|
			# Keep the connection, the decoder and the cursor in the state, not the
			# callback capture, so Finished can release them even when the
			# terminal continuation is retained.
			Stream.custom(
				NotStarted({ db, query, decoder }),
				Unknown,
				|state| {
					started = match state {
						Finished => {
							return Err(NoMore)
						}
						Running(running) => Ok(running)
						NotStarted(first) =>
							match start!(first.db, first.query, first.decoder) {
								Ok(cursor) => Ok({ cursor, row_decoder: first.decoder })
								Err(stopped) => Err(stopped)
							}
					}
					match started {
						Err(Closed) => Ok((Err(Closed), Finished))
						Err(SqliteErr(err)) => Ok((Err(SqliteErr(err)), Finished))
						Ok(running) =>
							match next_cells!(running.cursor) {
								Ok(cells) =>
									match decode_cells(running.cursor, running.row_decoder, cells) {
										Ok(value) => Ok((Ok(value), Running(running)))
										Err(err) => Ok((Err(BadRow(err)), Running(running)))
									}
								Err(Done) => Err(NoMore)
								Err(Closed) => Ok((Err(Closed), Finished))
								Err(SqliteErr(err)) => Ok((Err(SqliteErr(err)), Finished))
							}
					}
				},
			)

		## Run `body!` inside a transaction: `BEGIN`, the body, then `COMMIT`.
		##
		## If the body returns `Err`, the transaction is rolled back and that
		## error is returned; a rollback that fails is ignored. If `COMMIT`
		## fails, its error is returned and the transaction is rolled back.
		## SQLite has no nested transactions: calling this inside another
		## transaction fails at `BEGIN` and leaves the outer one untouched.
		##
		## ```roc
		## db.transaction!(|| {
		##     for todo in todos {
		##         db.execute!("INSERT INTO todos (task, status) VALUES (${String(todo.task)}, ${String(todo.status)})")?
		##     }
		##     Ok({})
		## })?
		## ```
		# TODO(roc-lang/roc#12263): change the callback type back to
		# `(() => Try(a, [..errs]))` once the compiler accepts it.
		transaction! : Db, (() => Try(a, [SqliteErr(Err), Closed, ..errs])) => Try(a, [SqliteErr(Err), Closed, ..errs])
		transaction! = |db, body!| {
			run_sql!(db, "BEGIN")?
			match body!() {
				Ok(value) =>
					match run_sql!(db, "COMMIT") {
						Ok({}) => Ok(value)
						Err(Closed) => Err(Closed)
						Err(SqliteErr(err)) => {
							_rolled_back = run_sql!(db, "ROLLBACK")
							Err(SqliteErr(err))
						}
					}
				Err(err) => {
					_rolled_back = run_sql!(db, "ROLLBACK")
					Err(err)
				}
			}
		}
	}

	## SQL text and the values of its parameters.
	##
	## A string literal is a `Query`. Each `${…}` in it must be a [Value] and
	## becomes a bound parameter (`?1`, `?2`, …), so the value is never parsed
	## as SQL:
	##
	## ```roc
	## db.execute!("UPDATE todos SET status = ${String(status)} WHERE id = ${Integer(id)}")?
	## ```
	##
	## A `${…}` inside `'…'`, `"…"` or a comment would be text, not a
	## parameter, so such a literal is rejected at compile time; write
	## `name = ${String(name)}`, not `name = '${String(name)}'`.
	Query :: { sql : Str, params : List(Value) }.{

		## A string literal without interpolation: SQL with no parameters.
		from_quote : Str -> Try(Query, [BadQuotedBytes(Str)])
		from_quote = |sql| Ok(Query.{ sql, params: [] })

		## An interpolated string literal: each `${…}` is a bound parameter.
		from_interpolation : List(Str) -> Try((List(Value) -> Query), [InvalidInterpolation(Str)])
		from_interpolation = |segments|
			match sql_from_segments(segments) {
				Ok(sql) => Ok(|params| Query.{ sql, params })
				Err(message) => Err(InvalidInterpolation(message))
			}

		## SQL assembled at run time, with the values for its `?` markers in
		## order. A count that differs from the statement's number of
		## parameters is `WrongParamCount` when the query is run.
		##
		## ```roc
		## marks = Str.join_with(ids.map(|_| "?"), ", ")
		## query = Query.new("SELECT task FROM todos WHERE id IN (${marks})", ids.map(|id| Integer(id)))
		## ```
		new : Str, List(Value) -> Query
		new = |sql, params| Query.{ sql, params }
	}

	## A result column, by name or by position counted from zero. A string
	## literal is a name and a number literal is a position:
	## `Decoder.i64("id")`, `Decoder.i64(0)`.
	##
	## A name must match the column's name in the result exactly; give an
	## expression a name with `AS`. Where two columns have the same name, the
	## name selects the first.
	Column := [Name(Str), Index(U64)].{
		is_eq : _

		from_quote : Str -> Try(Column, [BadQuotedBytes(Str)])
		from_quote = |name| Ok(Name(name))

		from_numeral : Numeral -> Try(Column, [InvalidNumeral(Str)])
		from_numeral = |numeral|
			match U64.from_numeral(numeral) {
				Ok(index) => Ok(Index(index))
				Err(InvalidNumeral(message)) => Err(InvalidNumeral(message))
			}
	}

	## SQLite's primary result codes for a failure. A constraint violation
	## says which kind of constraint failed.
	ErrCode : [
		Error,
		Internal,
		Perm,
		Abort,
		Busy,
		Locked,
		NoMem,
		ReadOnly,
		Interrupt,
		Io,
		Corrupt,
		NotFound,
		Full,
		CanNotOpen,
		Protocol,
		Empty,
		Schema,
		TooBig,
		Constraint([Unique, PrimaryKey, ForeignKey, NotNull, Check, Other]),
		Mismatch,
		Misuse,
		NoLFS,
		AuthDenied,
		Format,
		OutOfRange,
		NotADatabase,
		Unknown(I64),
	]

	## Why a database call failed.
	##
	## `Failed` is an error reported by SQLite: its primary result code, its
	## [extended result code](https://www.sqlite.org/rescode.html) and its
	## message. The other variants mean the call does not fit the statement,
	## and are found before anything runs:
	##
	## - `ColumnNotFound`: a decoder reads a column the query does not return.
	## - `WrongParamCount`: the statement has `expected` parameters and the
	##   [Query] carries `given` values.
	## - `ReturnsRows`: a statement given to [Db.execute!] has result columns.
	## - `MultipleStatements`: the text holds more than one statement.
	Err := [
		Failed({ code : ErrCode, extended_code : I64, message : Str }),
		ColumnNotFound(Column),
		WrongParamCount({ expected : U64, given : U64 }),
		ReturnsRows,
		MultipleStatements,
	].{
		is_eq : _

		## Describe the error for display.
		to_str : Err -> Str
		to_str = |err|
			match err {
				Failed({ code, extended_code, message }) => "${message} (${code_name(code)}, extended result code ${extended_code.to_str()})"
				ColumnNotFound(Name(name)) => "the query returns no column named ${Str.inspect(name)}"
				ColumnNotFound(Index(index)) => "the query returns no column at index ${index.to_str()}"
				WrongParamCount({ expected, given }) => "wrong number of parameter values: the statement needs ${expected.to_str()}, but ${given.to_str()} were given"
				ReturnsRows => "the statement returns rows; run it with query_one!, query_all! or rows"
				MultipleStatements => "the SQL text holds more than one statement; run it with execute_script!"
			}
	}

	## What the leaf decoders report: a column holding another type than the
	## one asked for, or text that is not valid UTF-8.
	DecodeErr : [
		UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] }),
		BadUtf8({ problem : Str.Utf8Problem, index : U64 }),
	]

	## A whole result row, as decoded by [Decoder.row].
	Row : { column_names : List(Str), values : List(Value) }

	## How to turn a result row into an `a`, or fail with an `err`.
	##
	## Leaf decoders read one column. Records of decoders combine with the
	## record-builder suffix:
	##
	## ```roc
	## decode_todo : Decoder({ id : I64, task : Str }, Sqlite.DecodeErr)
	## decode_todo = { id: Decoder.i64("id"), task: Decoder.str("task") }.Decoder
	## ```
	##
	## A decoder's columns are looked up once per query, before its first row
	## is read; a column that is missing is `SqliteErr(ColumnNotFound(_))`.
	## A value the decoder rejects fails that row only, as `BadRow(err)`.
	##
	## SQLite stores a value with its own type, whatever the column was
	## declared as, and the leaf decoders do not convert: `i64` accepts only
	## an integer.
	Decoder(a, err) :: {
		columns : List(Column),
		whole_row : Bool,
		decode : RowView, U64 -> Try(a, err),
	}.{

		## Combine two decoders; this is what the record-builder suffix
		## `{ … }.Decoder` calls.
		map2 : Decoder(a, err), Decoder(b, err), (a, b -> c) -> Decoder(c, err)
		map2 = |first, second, combine| {
			first_decode = first.decode
			second_decode = second.decode
			second_offset = first.columns.len()
			Decoder.{
				columns: first.columns.concat(second.columns),
				whole_row: first.whole_row or second.whole_row,
				decode: |view, offset| {
					a = first_decode(view, offset)?
					b = second_decode(view, offset + second_offset)?
					Ok(combine(a, b))
				},
			}
		}

		## Transform the decoded value.
		map : Decoder(a, err), (a -> b) -> Decoder(b, err)
		map = |decoder, transform| {
			inner = decoder.decode
			Decoder.{
				columns: decoder.columns,
				whole_row: decoder.whole_row,
				decode: |view, offset| Ok(transform(inner(view, offset)?)),
			}
		}

		## Transform the decoded value with a function that can fail; its
		## error fails the row, beside the decoder's own errors.
		##
		## ```roc
		## Decoder.i64("age").map_try(|n| if n >= 0 { Ok(n) } else { Err(NegativeAge(n)) })
		## ```
		map_try : Decoder(a, err), (a -> Try(b, err)) -> Decoder(b, err)
		map_try = |decoder, transform| {
			inner = decoder.decode
			Decoder.{
				columns: decoder.columns,
				whole_row: decoder.whole_row,
				decode: |view, offset| transform(inner(view, offset)?),
			}
		}

		## Accept SQL `NULL`: the result is `Err(Null)` when every column the
		## decoder reads is `NULL`, and `Ok` of the decoded value otherwise.
		nullable : Decoder(a, err) -> Decoder(Try(a, [Null]), err)
		nullable = |decoder| {
			inner = decoder.decode
			count = decoder.columns.len()
			whole_row = decoder.whole_row
			Decoder.{
				columns: decoder.columns,
				whole_row,
				decode: |view, offset|
					if all_null(view, offset, count, whole_row) {
						Ok(Err(Null))
					} else {
						Ok(Ok(inner(view, offset)?))
					},
			}
		}

		## Decode an integer column.
		##
		## For a narrower type, convert with [map_try]:
		## `Decoder.i64("n").map_try(|n| n.to_u8_try().map_err(|OutOfRange| OutOfRange))`.
		# TODO(roc-lang/roc#12264): shorten the example to
		# `map_try(|n| n.to_u8_try())` once a builtin's one-tag error keeps its
		# tag when it joins the decoder's other errors.
		i64 : Column -> Decoder(I64, [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] })])
		i64 = |column|
			leaf(
				column,
				|view, offset|
					match cell_at(view, offset) {
						Integer(n) => Ok(n)
						other => Err(unexpected_type(view, offset, other))
					},
			)

		## Decode a floating-point column. An integer is not converted.
		f64 : Column -> Decoder(F64, [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] })])
		f64 = |column|
			leaf(
				column,
				|view, offset|
					match cell_at(view, offset) {
						Real(n) => Ok(n)
						other => Err(unexpected_type(view, offset, other))
					},
			)

		## Decode an integer column as a boolean, the way SQLite does: zero is
		## `False` and any other integer is `True`.
		bool : Column -> Decoder(Bool, [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] })])
		bool = |column|
			leaf(
				column,
				|view, offset|
					match cell_at(view, offset) {
						Integer(n) => Ok(n != 0)
						other => Err(unexpected_type(view, offset, other))
					},
			)

		## Decode a `BLOB` column.
		bytes : Column -> Decoder(List(U8), [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] })])
		bytes = |column|
			leaf(
				column,
				|view, offset|
					match cell_at(view, offset) {
						Bytes(b) => Ok(b)
						other => Err(unexpected_type(view, offset, other))
					},
			)

		## Decode a text column. Text that is not valid UTF-8 is `BadUtf8`.
		str : Column -> Decoder(Str, [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] }), BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
		str = |column|
			leaf(
				column,
				|view, offset|
					match cell_at(view, offset) {
						Text(utf8) => text(utf8)
						other => Err(unexpected_type(view, offset, other))
					},
			)

		## Decode a column of any type, keeping its type as a tag.
		value : Column -> Decoder(Value, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
		value = |column| leaf(column, |view, offset| value_from_cell(cell_at(view, offset)))

		## Decode every column of the row, with the column names.
		row : Decoder(Row, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
		row = Decoder.{
			columns: [],
			whole_row: True,
			decode: |view, _offset| {
				var $values = List.with_capacity(view.cells.len())
				for cell in view.cells {
					$values = $values.append(value_from_cell(cell)?)
				}
				Ok({ column_names: view.names, values: $values })
			},
		}
	}
}

# ---- internal helpers (module-private) -----------------------------------------

## One row as a decoder sees it: the statement's column names, the row's
## values, and for each column the decoder reads, in order, its position.
RowView : { names : List(Str), cells : List(InternalSqlite.Cell), indexes : List(U64) }

## A running statement and the positions of the decoder's columns in it.
Cursor : { rows : Resource.SqliteRows, names : List(Str), indexes : List(U64) }

leaf : Sqlite.Column, (RowView, U64 -> Try(a, err)) -> Sqlite.Decoder(a, err)
leaf = |column, decode| Sqlite.Decoder.{ columns: [column], whole_row: False, decode }

## The value of the decoder's column number `offset`. The indexes were checked
## against the statement's column count when the decoder was resolved, and the
## host returns one cell per column.
cell_at : RowView, U64 -> InternalSqlite.Cell
cell_at = |view, offset|
	match view.indexes.get(offset) {
		Ok(index) => view.cells.get(index) ?? Null
		Err(OutOfBounds) => Null
	}

name_at : RowView, U64 -> Str
name_at = |view, offset|
	match view.indexes.get(offset) {
		Ok(index) => view.names.get(index) ?? ""
		Err(OutOfBounds) => ""
	}

unexpected_type : RowView, U64, InternalSqlite.Cell -> [UnexpectedType({ column : Str, found : [Null, Integer, Real, String, Bytes] })]
unexpected_type = |view, offset, cell| {
	found = match cell {
		Null => Null
		Integer(_) => Integer
		Real(_) => Real
		Text(_) => String
		Bytes(_) => Bytes
	}
	UnexpectedType({ column: name_at(view, offset), found })
}

text : List(U8) -> Try(Str, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
text = |utf8|
	match Str.from_utf8(utf8) {
		Ok(str) => Ok(str)
		Err(BadUtf8(problem)) => Err(BadUtf8(problem))
	}

value_from_cell : InternalSqlite.Cell -> Try(Sqlite.Value, [BadUtf8({ problem : Str.Utf8Problem, index : U64 })])
value_from_cell = |cell|
	match cell {
		Null => Ok(Null)
		Integer(n) => Ok(Integer(n))
		Real(n) => Ok(Real(n))
		Text(utf8) => Ok(String(text(utf8)?))
		Bytes(b) => Ok(Bytes(b))
	}

is_null : InternalSqlite.Cell -> Bool
is_null = |cell|
	match cell {
		Null => True
		_ => False
	}

all_null : RowView, U64, U64, Bool -> Bool
all_null = |view, offset, count, whole_row|
	if whole_row {
		view.cells.all(is_null)
	} else {
		view.indexes.drop_first(offset).take_first(count).all(|index| is_null(view.cells.get(index) ?? Null))
	}

## Find each column's position among the statement's column names.
resolve : List(Sqlite.Column), List(Str) -> Try(List(U64), Sqlite.Column)
resolve = |columns, names| {
	var $indexes = List.with_capacity(columns.len())
	for column in columns {
		index = match column {
			Name(name) =>
				match names.find_first_index(|candidate| candidate == name) {
					Ok(found) => found
					Err(NotFound) => {
						return Err(column)
					}
				}
			Index(position) =>
				if position < names.len() {
					position
				} else {
					return Err(column)
				}
		}
		$indexes = $indexes.append(index)
	}
	Ok($indexes)
}

## Prepare and bind the query, then resolve the decoder against its columns.
start! : Sqlite.Db, Sqlite.Query, Sqlite.Decoder(a, err) => Try(Cursor, [SqliteErr(Sqlite.Err), Closed])
start! = |db, query, decoder|
	match Host.sqlite_query!(db.host, query.sql, query.params) {
		Ok(rows) => {
			names = Host.sqlite_columns!(rows)
			match resolve(decoder.columns, names) {
				Ok(indexes) => Ok({ rows, names, indexes })
				Err(column) => Err(SqliteErr(ColumnNotFound(column)))
			}
		}
		Err(problem) => Err(widen_problem(problem))
	}

next_cells! : Cursor => Try(List(InternalSqlite.Cell), [Done, Closed, SqliteErr(Sqlite.Err)])
next_cells! = |cursor|
	match Host.sqlite_next!(cursor.rows) {
		Ok(cells) => Ok(cells)
		Err(Done) => Err(Done)
		Err(Closed) => Err(Closed)
		Err(Failed(failure)) => Err(SqliteErr(failed(failure)))
	}

decode_cells : Cursor, Sqlite.Decoder(a, err), List(InternalSqlite.Cell) -> Try(a, err)
decode_cells = |cursor, decoder, cells| {
	decode = decoder.decode
	decode({ names: cursor.names, cells, indexes: cursor.indexes }, 0)
}

run_sql! : Sqlite.Db, Str => Try({}, [SqliteErr(Sqlite.Err), Closed])
run_sql! = |db, sql|
	match Host.sqlite_execute!(db.host, sql, []) {
		Ok({}) => Ok({})
		Err(problem) => Err(widen_problem(problem))
	}

widen_problem : InternalSqlite.Problem -> [SqliteErr(Sqlite.Err), Closed]
widen_problem = |problem|
	match problem {
		Failed(failure) => SqliteErr(failed(failure))
		Closed => Closed
		WrongParamCount(counts) => SqliteErr(WrongParamCount(counts))
		ReturnsRows => SqliteErr(ReturnsRows)
		MultipleStatements => SqliteErr(MultipleStatements)
	}

failed : InternalSqlite.Failure -> Sqlite.Err
failed = |{ extended_code, message }|
	Failed({ code: code_from_extended(extended_code), extended_code, message })

## The primary result code is the low byte of the extended one.
code_from_extended : I64 -> Sqlite.ErrCode
code_from_extended = |extended|
	match extended % 256 {
		1 => Error
		2 => Internal
		3 => Perm
		4 => Abort
		5 => Busy
		6 => Locked
		7 => NoMem
		8 => ReadOnly
		9 => Interrupt
		10 => Io
		11 => Corrupt
		12 => NotFound
		13 => Full
		14 => CanNotOpen
		15 => Protocol
		16 => Empty
		17 => Schema
		18 => TooBig
		19 =>
			Constraint(
				match extended // 256 {
					1 => Check
					3 => ForeignKey
					5 => NotNull
					6 => PrimaryKey
					8 => Unique
					_ => Other
				},
			)
		20 => Mismatch
		21 => Misuse
		22 => NoLFS
		23 => AuthDenied
		24 => Format
		25 => OutOfRange
		26 => NotADatabase
		_ => Unknown(extended)
	}

code_name : Sqlite.ErrCode -> Str
code_name = |code|
	match code {
		Constraint(kind) => "Constraint(${Str.inspect(kind)})"
		Unknown(n) => "Unknown(${n.to_str()})"
		other => Str.inspect(other)
	}

## Where the SQL lexer is between two bytes of a literal.
SqlState : [Plain, Dash, Slash, LineComment, BlockComment, BlockCommentStar, SingleQuoted, DoubleQuoted, Backticked, Bracketed]

sql_step : SqlState, U8 -> SqlState
sql_step = |state, byte|
	match state {
		Plain => sql_plain(byte)
		Dash => if byte == '-' {
			LineComment
		} else {
			sql_plain(byte)
		}
		Slash => if byte == '*' {
			BlockComment
		} else {
			sql_plain(byte)
		}
		LineComment => if byte == '\n' {
			Plain
		} else {
			LineComment
		}
		BlockComment => if byte == '*' {
			BlockCommentStar
		} else {
			BlockComment
		}
		BlockCommentStar =>
			if byte == '/' {
				Plain
			} else if byte == '*' {
				BlockCommentStar
			} else {
				BlockComment
			}
		SingleQuoted => if byte == '\'' {
			Plain
		} else {
			SingleQuoted
		}
		DoubleQuoted => if byte == '"' {
			Plain
		} else {
			DoubleQuoted
		}
		Backticked => if byte == '`' {
			Plain
		} else {
			Backticked
		}
		Bracketed => if byte == ']' {
			Plain
		} else {
			Bracketed
		}
	}

sql_plain : U8 -> SqlState
sql_plain = |byte|
	match byte {
		'-' => Dash
		'/' => Slash
		'\'' => SingleQuoted
		'"' => DoubleQuoted
		'`' => Backticked
		'[' => Bracketed
		_ => Plain
	}

## Join a literal's segments with numbered parameter markers, refusing a
## literal in which an interpolation would not be a parameter.
sql_from_segments : List(Str) -> Try(Str, Str)
sql_from_segments = |segments| {
	var $sql = ""
	var $state = Plain
	var $next_param = 1
	last = segments.len() - 1
	for segment in segments {
		for byte in segment.to_utf8() {
			if $state == Plain and byte == '?' {
				return Err("a `?` marker cannot be mixed with interpolated parameters; interpolate the value, or use Query.new")
			}
			$state = sql_step($state, byte)
		}
		$sql = $sql.concat(segment)
		if $next_param <= last {
			match $state {
				Plain | Dash | Slash => {
					$sql = $sql.concat("?${$next_param.to_str()}")
					$state = Plain
					$next_param = $next_param + 1
				}
				_ => {
					return Err("an interpolation inside a quoted SQL string or a comment is not a parameter; remove the quotes")
				}
			}
		}
	}
	Ok($sql)
}

expect sql_from_segments(["SELECT 1"]) == Ok("SELECT 1")
expect sql_from_segments(["a = ", " AND b = ", ""]) == Ok("a = ?1 AND b = ?2")
expect sql_from_segments(["a = 'it''s' AND b = ", " -- trailing ' comment"]) == Ok("a = 'it''s' AND b = ?1 -- trailing ' comment")
expect sql_from_segments(["a - ", " / ", " /* c */ -- d\n + ", ""]) == Ok("a - ?1 / ?2 /* c */ -- d\n + ?3")
expect sql_from_segments(["a -", "- 1"]) == Ok("a -?1- 1")
expect sql_from_segments(["name = '", "'"]).is_err()
expect sql_from_segments(["name = \"", "\""]).is_err()
expect sql_from_segments(["a -- ", "\n"]).is_err()
expect sql_from_segments(["a /* ", " */"]).is_err()
expect sql_from_segments(["a /* * ", " */"]).is_err()
expect sql_from_segments(["a `", "`"]).is_err()
expect sql_from_segments(["a [", "]"]).is_err()
expect sql_from_segments(["a = ? AND b = ", ""]).is_err()
expect sql_from_segments(["a = '?' AND b = ", ""]) == Ok("a = '?' AND b = ?1")

expect resolve([Name("b"), Index(0), Name("a")], ["a", "b"]) == Ok([1, 0, 0])
expect resolve([Name("a"), Name("c")], ["a", "b"]) == Err(Name("c"))
expect resolve([Index(2)], ["a", "b"]) == Err(Index(2))
expect resolve([], []) == Ok([])

expect code_from_extended(5) == Busy
expect code_from_extended(261) == Busy
expect code_from_extended(10) == Io
expect code_from_extended(2067) == Constraint(Unique)
expect code_from_extended(1555) == Constraint(PrimaryKey)
expect code_from_extended(787) == Constraint(ForeignKey)
expect code_from_extended(1299) == Constraint(NotNull)
expect code_from_extended(275) == Constraint(Check)
expect code_from_extended(19) == Constraint(Other)
expect code_from_extended(2579) == Constraint(Other)
expect code_from_extended(0) == Unknown(0)
expect code_from_extended(27) == Unknown(27)
expect code_from_extended(100) == Unknown(100)
expect code_from_extended(101) == Unknown(101)

## Resolve a decoder against a statement's columns and decode one row, the
## way a query does; only the expects below use it.
decode_one : Sqlite.Decoder(a, err), List(Str), List(InternalSqlite.Cell) -> Try(Try(a, err), Sqlite.Column)
decode_one = |decoder, names, cells| {
	indexes = resolve(decoder.columns, names)?
	decode = decoder.decode
	Ok(decode({ names, cells, indexes }, 0))
}

expect decode_one(Sqlite.Decoder.i64("b"), ["a", "b"], [Integer(1), Integer(2)]) == Ok(Ok(2))
expect decode_one(Sqlite.Decoder.i64(0), ["a", "b"], [Integer(1), Integer(2)]) == Ok(Ok(1))
expect decode_one(Sqlite.Decoder.i64("c"), ["a", "b"], [Integer(1), Integer(2)]) == Err(Name("c"))
expect decode_one(Sqlite.Decoder.i64("a"), ["a"], [Real(1.5)]) == Ok(Err(UnexpectedType({ column: "a", found: Real })))
expect decode_one(Sqlite.Decoder.f64("a"), ["a"], [Integer(1)]) == Ok(Err(UnexpectedType({ column: "a", found: Integer })))
expect decode_one(Sqlite.Decoder.bool("a"), ["a"], [Integer(0)]) == Ok(Ok(False))
expect decode_one(Sqlite.Decoder.bool("a"), ["a"], [Integer(-3)]) == Ok(Ok(True))
expect decode_one(Sqlite.Decoder.bytes("a"), ["a"], [Text([104, 105])]) == Ok(Err(UnexpectedType({ column: "a", found: String })))
expect decode_one(Sqlite.Decoder.str("a"), ["a"], [Text([104, 105])]) == Ok(Ok("hi"))
expect decode_one(Sqlite.Decoder.str("a"), ["a"], [Bytes([104, 105])]) == Ok(Err(UnexpectedType({ column: "a", found: Bytes })))
expect decode_one(Sqlite.Decoder.str("a"), ["a"], [Text([255])]).map_ok(|result| result.is_err()) == Ok(True)
expect decode_one(Sqlite.Decoder.value("a"), ["a"], [Text([104, 105])]) == Ok(Ok(String("hi")))
expect decode_one(Sqlite.Decoder.value("a"), ["a"], [Null]) == Ok(Ok(Null))
expect decode_one(Sqlite.Decoder.row, ["a", "b"], [Integer(1), Bytes([2])]) == Ok(Ok({ column_names: ["a", "b"], values: [Integer(1), Bytes([2])] }))
expect decode_one(Sqlite.Decoder.i64("a").map(|n| n + 1), ["a"], [Integer(1)]) == Ok(Ok(2))

# `nullable` is `Err(Null)` only when every column the decoder reads is NULL;
# other columns of the row do not count, and offsets carry through `map2`.
expect decode_one(Sqlite.Decoder.i64("a").nullable(), ["a", "b"], [Null, Integer(2)]) == Ok(Ok(Err(Null)))
expect decode_one(Sqlite.Decoder.i64("a").nullable(), ["a", "b"], [Integer(1), Null]) == Ok(Ok(Ok(1)))
expect decode_one(Sqlite.Decoder.row.nullable(), ["a", "b"], [Null, Null]) == Ok(Ok(Err(Null)))
expect decode_one(Sqlite.Decoder.row.nullable(), ["a", "b"], [Null, Integer(2)]) == Ok(Ok(Ok({ column_names: ["a", "b"], values: [Null, Integer(2)] })))
expect {
	pair = Sqlite.Decoder.map2(Sqlite.Decoder.i64("b"), Sqlite.Decoder.i64("c"), |b, c| (b, c)).nullable()
	both = Sqlite.Decoder.map2(Sqlite.Decoder.i64("a"), pair, |a, rest| (a, rest))
	names = ["a", "b", "c"]
	decode_one(both, names, [Integer(1), Null, Null]) == Ok(Ok((1, Err(Null))))
		and decode_one(both, names, [Integer(1), Integer(2), Integer(3)]) == Ok(Ok((1, Ok((2, 3)))))
			and decode_one(both, names, [Integer(1), Null, Integer(3)]) == Ok(Err(UnexpectedType({ column: "b", found: Null })))
				and decode_one(both, names, [Null, Null, Null]) == Ok(Err(UnexpectedType({ column: "a", found: Null })))
}
