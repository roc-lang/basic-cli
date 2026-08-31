import InternalSqlite
import Host
import Path

# Porting notes for the new (zig) compiler: the decoder combinator API is written
# with fully-literal nested lambdas (`|name| |cols| |stmt| ...`) and relies on
# structural type inference. This is deliberate — the current compiler (a) treats
# an associated member whose body returns a function via a non-lambda expression as
# a hosted declaration, and (b) does not unify an associated `:` type alias (e.g.
# `Value`) with the structural tag union it aliases when used as a function
# parameter, nor support open tag-union extension (`[Tag]ext`) in annotations. So
# the decoders are left unannotated and all decoder errors live in one closed set
# of tags (see DecodeErr below for the documented shape).
## Execute SQLite statements and decode rows using either one-shot or reusable
## prepared APIs. Application code works with the public `Value`, `Binding`,
## `Stmt`, and `ErrCode` types below; raw host ABI records remain internal.
##
## Database paths use basic-cli's byte-preserving `Path` type.
## See the [host runtime behavior](https://github.com/roc-lang/basic-cli#host-runtime-behavior)
## for connection caching and lifetime details.
Sqlite :: [].{

	## A value accepted by a SQLite binding or returned from a column.
	Value : [
		Null,
		Real(F64),
		Integer(I64),
		String(Str),
		Bytes(List(U8)),
	]

	## A named parameter binding. Include SQLite's parameter prefix in `name`,
	## for example `{ name: ":id", value: Integer(42) }`.
	Binding : {
		name : Str,
		value : Value,
	}

	## Represents a prepared statement that can be executed many times.
	Stmt :: { host : Host.SqliteStmt }.{

		## Render the statement without exposing its host handle.
		to_inspect : Stmt -> Str
		to_inspect = |_| "Sqlite.Stmt(<opaque>)"

		## Execute this prepared statement without returning rows.
		execute! : Stmt, List(Binding) => Try({}, [RowsReturnedUseQueryInstead, SqliteErr(ErrCode, Str), ..])
		execute! = |stmt, bindings| {
			host_stmt = stmt_to_host(stmt)
			sqlite_bind!(host_stmt, bindings)?
			res = sqlite_step!(host_stmt)
			sqlite_reset!(host_stmt)?
			match res {
				Ok(Done) => Ok({})
				Ok(Row) => Err(RowsReturnedUseQueryInstead)
				Err(e) => Err(e)
			}
		}

		## Execute this prepared query and decode exactly one row.
		query! = |stmt, bindings, decode| {
			host_stmt = stmt_to_host(stmt)
			sqlite_bind!(host_stmt, bindings)?
			res = decode_exactly_one_row!(host_stmt, decode)
			sqlite_reset!(host_stmt)?
			res
		}

		## Execute this prepared query and decode all returned rows.
		query_many! = |stmt, bindings, decode| {
			host_stmt = stmt_to_host(stmt)
			sqlite_bind!(host_stmt, bindings)?
			res = decode_rows!(host_stmt, decode)
			sqlite_reset!(host_stmt)?
			res
		}
	}

	## Represents various error codes that can be returned by Sqlite.
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
		IOErr,
		Corrupt,
		NotFound,
		Full,
		CanNotOpen,
		Protocol,
		Empty,
		Schema,
		TooBig,
		Constraint,
		Mismatch,
		Misuse,
		NoLFS,
		AuthDenied,
		Format,
		OutOfRange,
		NotADatabase,
		Notice,
		Warning,
		Row,
		Done,
		Unknown(I64),
	]

	## Documented shape of the errors a decoder can produce (the decoders below are
	## left unannotated and infer a subset of these structurally):
	## ```
	## [
	##     NoSuchField(Str),
	##     SqliteErr(ErrCode, Str),
	##     UnexpectedType([Integer, Real, String, Bytes, Null]),
	##     FailedToDecodeInteger,
	##     FailedToDecodeReal,
	##     IntOutOfBounds,
	##     NoRowsReturned,
	##     TooManyRowsReturned,
	## ]
	## ```
	DecodeErr : [NoSuchField(Str), SqliteErr(ErrCode, Str)]

	## Prepare a `Stmt` for reuse by the prepared execute and query operations.
	prepare! : { path : Path.Path, query : Str } => Try(Stmt, [SqliteErr(ErrCode, Str), ..])
	prepare! = |{ path, query: q }|
		sqlite_prepare!(Path.to_raw(path), q).map_ok(|stmt| Stmt.{ host: stmt })

	## Execute a SQL statement that **doesn't return any rows** (INSERT/UPDATE/DELETE).
	execute! : { path : Path.Path, query : Str, bindings : List(Binding) } => Try({}, [RowsReturnedUseQueryInstead, SqliteErr(ErrCode, Str), ..])
	execute! = |{ path, query: q, bindings }| {
		stmt = prepare!({ path, query: q })?
		stmt.execute!(bindings)
	}

	## Execute a SQL query and decode exactly one row into a value. `bindings`
	## is a `List(Binding)` and `row` is a decoder built from the functions below.
	query! = |{ path, query: q, bindings, row }| {
		stmt = prepare!({ path, query: q })?
		stmt.query!(bindings, row)
	}

	## Execute a SQL query and decode multiple rows into a list of values.
	## `bindings` is a `List(Binding)` and `rows` is a row decoder.
	query_many! = |{ path, query: q, bindings, rows }| {
		stmt = prepare!({ path, query: q })?
		stmt.query_many!(bindings, rows)
	}

	# ---- Row decoding combinators ----------------------------------------------

	## Decode a Sqlite row into a record by combining two decoders.
	decode_record = |gen_first, gen_second, mapper|
		|cols|
			|stmt|
				match gen_first(cols)(stmt) {
					Ok(first) =>
						match gen_second(cols)(stmt) {
							Ok(second) => Ok(mapper(first, second))
							Err(e) => Err(e)
						}
					Err(e) => Err(e)
				}

	## Transform the output of a decoder by applying a function to the decoded value.
	map_value = |gen_decode, mapper|
		|cols|
			|stmt|
				match gen_decode(cols)(stmt) {
					Ok(val) => Ok(mapper(val))
					Err(e) => Err(e)
				}

	## Transform a decoder's output with a function returning a `Try`.
	map_value_result = |gen_decode, mapper|
		|cols|
			|stmt|
				match gen_decode(cols)(stmt) {
					Ok(val) => mapper(val)
					Err(e) => Err(e)
				}

	# ---- Leaf decoders ---------------------------------------------------------

	## Decode a `Value` keeping it tagged.
	tagged_value = |name|
		|cols|
			|stmt| lookup_value!(cols, stmt, name)

	## Decode a column to a `Str`.
	str = |name|
		|cols|
			|stmt|
				match lookup_value!(cols, stmt, name) {
					Ok(String(s)) => Ok(s)
					Ok(other) => to_unexpected_type_err(other)
					Err(e) => Err(e)
				}

	## Decode a column to a [List U8].
	bytes = |name|
		|cols|
			|stmt|
				match lookup_value!(cols, stmt, name) {
					Ok(Bytes(b)) => Ok(b)
					Ok(other) => to_unexpected_type_err(other)
					Err(e) => Err(e)
				}

	## Decode a column to an `I64`.
	i64 = |name| int_decoder(name, |n| Ok(n))

	## Decode a column to an `I32`.
	i32 = |name| int_decoder(name, |n| bounds_err(I64.to_i32_try(n)))

	## Decode a column to an `I16`.
	i16 = |name| int_decoder(name, |n| bounds_err(I64.to_i16_try(n)))

	## Decode a column to an `I8`.
	i8 = |name| int_decoder(name, |n| bounds_err(I64.to_i8_try(n)))

	## Decode a column to a `U64`.
	u64 = |name| int_decoder(name, |n| bounds_err(I64.to_u64_try(n)))

	## Decode a column to a `U32`.
	u32 = |name| int_decoder(name, |n| bounds_err(I64.to_u32_try(n)))

	## Decode a column to a `U16`.
	u16 = |name| int_decoder(name, |n| bounds_err(I64.to_u16_try(n)))

	## Decode a column to a `U8`.
	u8 = |name| int_decoder(name, |n| bounds_err(I64.to_u8_try(n)))

	## Decode a column to an `F64`.
	f64 = |name| real_decoder(name, |r| Ok(r))

	# Nullable decoders return `NotNull(value)` for a present value, or `Null` when
	# the column holds SQL NULL. Useful for nullable columns.

	## Decode a nullable column to `[NotNull(Str), Null]`.
	nullable_str = |name|
		|cols|
			|stmt|
				match lookup_value!(cols, stmt, name) {
					Ok(String(s)) => Ok(NotNull(s))
					Ok(Null) => Ok(Null)
					Ok(other) => to_unexpected_type_err(other)
					Err(e) => Err(e)
				}

	## Decode a nullable column to `[NotNull(List(U8)), Null]`.
	nullable_bytes = |name|
		|cols|
			|stmt|
				match lookup_value!(cols, stmt, name) {
					Ok(Bytes(b)) => Ok(NotNull(b))
					Ok(Null) => Ok(Null)
					Ok(other) => to_unexpected_type_err(other)
					Err(e) => Err(e)
				}

	## Decode a nullable column to `[NotNull(I64), Null]`.
	nullable_i64 = |name| nullable_int_decoder(name, |n| Ok(n))

	## Decode a nullable column to `[NotNull(I32), Null]`.
	nullable_i32 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i32_try(n)))

	## Decode a nullable column to `[NotNull(I16), Null]`.
	nullable_i16 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i16_try(n)))

	## Decode a nullable column to `[NotNull(I8), Null]`.
	nullable_i8 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_i8_try(n)))

	## Decode a nullable column to `[NotNull(U64), Null]`.
	nullable_u64 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u64_try(n)))

	## Decode a nullable column to `[NotNull(U32), Null]`.
	nullable_u32 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u32_try(n)))

	## Decode a nullable column to `[NotNull(U16), Null]`.
	nullable_u16 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u16_try(n)))

	## Decode a nullable column to `[NotNull(U8), Null]`.
	nullable_u8 = |name| nullable_int_decoder(name, |n| bounds_err(I64.to_u8_try(n)))

	## Decode a nullable column to `[NotNull(F64), Null]`.
	nullable_f64 = |name| nullable_real_decoder(name, |r| Ok(r))

	## Convert an `ErrCode` to a pretty string for display purposes.
	errcode_to_str = |code|
		match code {
			Error => "Error: Sql error or missing database"
			Internal => "Internal: Internal logic error in Sqlite"
			Perm => "Perm: Access permission denied"
			Abort => "Abort: Callback routine requested an abort"
			Busy => "Busy: The database file is locked"
			Locked => "Locked: A table in the database is locked"
			NoMem => "NoMem: A malloc() failed"
			ReadOnly => "ReadOnly: Attempt to write a readonly database"
			Interrupt => "Interrupt: Operation terminated by sqlite3_interrupt("
			IOErr => "IOErr: Some kind of disk I/O error occurred"
			Corrupt => "Corrupt: The database disk image is malformed"
			NotFound => "NotFound: Unknown opcode in sqlite3_file_control()"
			Full => "Full: Insertion failed because database is full"
			CanNotOpen => "CanNotOpen: Unable to open the database file"
			Protocol => "Protocol: Database lock protocol error"
			Empty => "Empty: Database is empty"
			Schema => "Schema: The database schema changed"
			TooBig => "TooBig: String or BLOB exceeds size limit"
			Constraint => "Constraint: Abort due to constraint violation"
			Mismatch => "Mismatch: Data type mismatch"
			Misuse => "Misuse: Library used incorrectly"
			NoLFS => "NoLFS: Uses OS features not supported on host"
			AuthDenied => "AuthDenied: Authorization denied"
			Format => "Format: Auxiliary database format error"
			OutOfRange => "OutOfRange: 2nd parameter to sqlite3_bind out of range"
			NotADatabase => "NotADatabase: File opened that is not a database file"
			Notice => "Notice: Notifications from sqlite3_log()"
			Warning => "Warning: Warnings from sqlite3_log()"
			Row => "Row: sqlite3_step() has another row ready"
			Done => "Done: sqlite3_step() has finished executing"
			Unknown(c) => "Unknown: error code ${I64.to_str(c)} not known"
		}
}

# ---- internal helpers (module-private) -----------------------------------------

stmt_to_host : Sqlite.Stmt -> Host.SqliteStmt
stmt_to_host = |stmt| stmt.host

sqlite_prepare! = |raw_path, query|
	Host.sqlite_prepare!(raw_path, query)
		.map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

sqlite_bind! : Host.SqliteStmt, List({ name : Str, value : [Null, Real(F64), Integer(I64), String(Str), Bytes(List(U8))] }) => Try({}, [SqliteErr(Sqlite.ErrCode, Str), ..])
sqlite_bind! = |stmt, bindings|
	Host.sqlite_bind!(stmt, bindings)
		.map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

sqlite_columns! = |stmt| Host.sqlite_columns!(stmt)

sqlite_column_value! = |stmt, index|
	Host.sqlite_column_value!(stmt, index)
		.map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

sqlite_step! : Host.SqliteStmt => Try([Row, Done], [SqliteErr(Sqlite.ErrCode, Str), ..])
sqlite_step! = |stmt|
	match Host.sqlite_step!(stmt) {
		Ok(has_row) => if has_row {
			Ok(Row)
		} else {
			Ok(Done)
		}
		Err({ code, message }) => Err(SqliteErr(code_from_i64(code), message))
	}

sqlite_reset! : Host.SqliteStmt => Try({}, [SqliteErr(Sqlite.ErrCode, Str), ..])
sqlite_reset! = |stmt|
	Host.sqlite_reset!(stmt)
		.map_err(|{ code, message }| SqliteErr(code_from_i64(code), message))

decode_exactly_one_row! = |stmt, gen_decode| {
	cols = sqlite_columns!(stmt)
	decode_row! = gen_decode(cols)
	match sqlite_step!(stmt)? {
		Row => {
			row = decode_row!(stmt)?
			match sqlite_step!(stmt)? {
				Done => Ok(row)
				Row => Err(TooManyRowsReturned)
			}
		}
		Done => Err(NoRowsReturned)
	}
}

decode_rows! = |stmt, gen_decode| {
	cols = sqlite_columns!(stmt)
	decode_row! = gen_decode(cols)
	helper! = |out|
		match sqlite_step!(stmt)? {
			Done => Ok(out)
			Row => {
				row = decode_row!(stmt)?
				helper!(out.append(row))
			}
		}
	helper!([])
}

lookup_value! = |cols, stmt, name|
	match List.find_first_index(cols, |x| x == name) {
		Ok(index) => sqlite_column_value!(stmt, index)
		Err(NotFound) => Err(NoSuchField(name))
	}

nullable_int_decoder = |name, cast|
	|cols|
		|stmt|
			match lookup_value!(cols, stmt, name) {
				Ok(Integer(n)) =>
					match cast(n) {
						Ok(v) => Ok(NotNull(v))
						Err(e) => Err(e)
					}
				Ok(Null) => Ok(Null)
				Ok(other) => to_unexpected_type_err(other)
				Err(e) => Err(e)
			}

nullable_real_decoder = |name, cast|
	|cols|
		|stmt|
			match lookup_value!(cols, stmt, name) {
				Ok(Real(r)) =>
					match cast(r) {
						Ok(v) => Ok(NotNull(v))
						Err(e) => Err(e)
					}
				Ok(Null) => Ok(Null)
				Ok(other) => to_unexpected_type_err(other)
				Err(e) => Err(e)
			}

int_decoder = |name, cast|
	|cols|
		|stmt|
			match lookup_value!(cols, stmt, name) {
				Ok(Integer(n)) => cast(n)
				Ok(other) => to_unexpected_type_err(other)
				Err(e) => Err(e)
			}

real_decoder = |name, cast|
	|cols|
		|stmt|
			match lookup_value!(cols, stmt, name) {
				Ok(Real(r)) => cast(r)
				Ok(other) => to_unexpected_type_err(other)
				Err(e) => Err(e)
			}

to_unexpected_type_err = |val| {
	type = match val {
		Integer(_) => Integer
		Real(_) => Real
		String(_) => String
		Bytes(_) => Bytes
		Null => Null
	}
	Err(UnexpectedType(type))
}

bounds_err = |result|
	match result {
		Ok(v) => Ok(v)
		Err(_) => Err(IntOutOfBounds)
	}

code_from_i64 : I64 -> Sqlite.ErrCode
code_from_i64 = |code|
	match code {
		0 => Error
		1 => Error
		2 => Internal
		3 => Perm
		4 => Abort
		5 => Busy
		6 => Locked
		7 => NoMem
		8 => ReadOnly
		9 => Interrupt
		10 => IOErr
		11 => Corrupt
		12 => NotFound
		13 => Full
		14 => CanNotOpen
		15 => Protocol
		16 => Empty
		17 => Schema
		18 => TooBig
		19 => Constraint
		20 => Mismatch
		21 => Misuse
		22 => NoLFS
		23 => AuthDenied
		24 => Format
		25 => OutOfRange
		26 => NotADatabase
		27 => Notice
		28 => Warning
		100 => Row
		101 => Done
		other => Unknown(other)
	}

## A row decoder written the way an application writes one.
## The compiler has to settle its type right here, before `query_many!`
## ever gets to say what `cols` is. Each call infers the type of `cols` separately,
## and since roc-lang/roc#10984 these types are no longer resolved together.
##
## The test is successful if this snippet compiles.
expect {
	_decode_row = |cols|
		|stmt| {
			id = Sqlite.i64("id")(cols)(stmt)?
			task = Sqlite.str("task")(cols)(stmt)?
			status = Sqlite.str("status")(cols)(stmt)?
			Ok({ id, task, status })
		}
	Bool.True
}
