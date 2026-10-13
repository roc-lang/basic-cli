## Print what `Sqlite` calls return for the cases the examples do not show, so
## that scripts/test.py can check them: stream order and early exit, closing,
## transactions, decoders, parameters and errors.
app [main!] { pf: platform "../platform/main.roc" }

import pf.Duration
import pf.Env
import pf.OsStr
import pf.Path
import pf.Sqlite
import pf.Sqlite.Decoder
import pf.Sqlite.Query
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"rows" => rows!()
		"query" => query!()
		"execute" => execute!()
		"transaction" => transaction!()
		"decoders" => decoders!()
		"params" => params!()
		"errors" => errors!()
		"close" => close!()
		"files" => Env.with_temp_dir!(files!)
		"error-rows" => error_rows!(args.len())
		_ => Err(UnknownMode(mode))
	}
}

show! : Str, a => Try({}, _)
show! = |label, value| Stdout.line!("${label}: ${Str.inspect(value)}")

Event : { id : I64, payload : Str }

decode_event : Decoder(Event, Sqlite.DecodeErr)
decode_event = { id: Decoder.i64("id"), payload: Decoder.str("payload") }.Decoder

## A database with four events; the payload of the second is not text.
events_db! : () => Try(Sqlite.Db, _)
events_db! = || {
	db = Sqlite.open_in_memory!()?
	db.execute_script!(
		\\CREATE TABLE events (id INTEGER PRIMARY KEY, payload);
		\\INSERT INTO events VALUES (1, 'one'), (2, 2.5), (3, 'three'), (4, 'four');
		,
	)?
	Ok(db)
}

## Collect a stream's items as text, one per line.
drain! : Stream(Try(a, [SqliteErr(Sqlite.Err), Closed, BadRow(err)])), Str => Try({}, _)
drain! = |stream, label| {
	for! item in stream {
		match item {
			Ok(value) => show!("${label} row", value)?
			Err(BadRow(err)) => show!("${label} bad row", err)?
			Err(SqliteErr(err)) => show!("${label} sqlite error", err)?
			Err(Closed) => Stdout.line!("${label}: closed")?
		}
	}
	Stdout.line!("${label}: end")
}

## Stop reading the events at the third. The loop has a function of its own
## so the stream is gone when it returns: an optimized build may keep a
## stream that a loop was left with `break` until the end of the function.
leave_early! : Sqlite.Db => Try({}, _)
leave_early! = |db| {
	for! item in db.rows("SELECT id, payload FROM events ORDER BY id", decode_event) {
		match item {
			Ok(event) if event.id >= 3 => break
			Ok(event) => show!("early row", event)?
			Err(BadRow(err)) => show!("early bad row", err)?
			Err(SqliteErr(err)) => {
				return Err(SqliteErr(err))
			}
			Err(Closed) => {
				return Err(Closed)
			}
		}
	}
	Ok({})
}

rows! : () => Try({}, _)
rows! = || {
	db = events_db!()?
	events = db.rows("SELECT id, payload FROM events ORDER BY id", decode_event)

	# A row that does not decode is an item, and the stream goes on.
	drain!(events, "all")?
	# A stream value can be run again: each run is a new query.
	db.execute!("DELETE FROM events WHERE id = ${Integer(2)}")?
	drain!(events, "again")?

	# Leaving the loop early releases the statement: a table cannot be
	# dropped while a statement is reading it.
	leave_early!(db)?
	show!("drop after break", db.execute!("DROP TABLE events"))?

	# A column the decoder names but the query does not return: the only item.
	drain!(db.rows("SELECT 1 AS id, 'x' AS pay_load", decode_event), "missing name")?
	drain!(db.rows("SELECT 1 AS id", Decoder.i64(1)), "missing index")?

	# SQLite failing part way through is the last item.
	db.execute_script!(
		\\CREATE TABLE numbers (n INTEGER);
		\\INSERT INTO numbers VALUES (-1), (-9223372036854775808), (-3);
		,
	)?
	drain!(db.rows("SELECT abs(n) AS n FROM numbers ORDER BY rowid", Decoder.i64("n")), "overflow")?
	# The failed statement was released too.
	show!("drop after failure", db.execute!("DROP TABLE numbers"))?

	# Errors found before the first row are the only item.
	drain!(db.rows("SELECT * FROM nowhere", Decoder.row), "no table")?
	drain!(db.rows(Query.new("SELECT ?", []), Decoder.row), "no value")?
	drain!(db.rows("SELECT 1; SELECT 2", Decoder.row), "two statements")?
	# Text with no statement returns no columns and no rows.
	drain!(db.rows("-- nothing", Decoder.row), "no statement")?
	drain!(db.rows("", Decoder.i64(0)), "no statement, a column")?
	# A statement without result columns runs, and has no rows.
	db.execute!("CREATE TABLE log (line TEXT)")?
	drain!(db.rows("INSERT INTO log VALUES ('x')", Decoder.row), "insert")?
	drain!(db.rows("INSERT INTO log VALUES ('y') RETURNING line", Decoder.str(0)), "returning")?
	show!("log", db.query_all!("SELECT line FROM log ORDER BY rowid", Decoder.str("line")))
}

query! : () => Try({}, _)
query! = || {
	db = events_db!()?
	by_id! = |id| db.query_one!("SELECT id, payload FROM events WHERE id = ${Integer(id)}", decode_event)

	show!("one", by_id!(3))?
	show!("no rows", by_id!(9))?
	show!("bad row", by_id!(2))?
	show!("too many", db.query_one!("SELECT id, payload FROM events", decode_event))?
	# The second row is reported before the first is decoded.
	show!("too many, first bad", db.query_one!("SELECT id, payload FROM events WHERE id IN (2, 3) ORDER BY id", decode_event))?
	show!("by index", db.query_one!("SELECT COUNT(*), MAX(id) FROM events", { count: Decoder.i64(0), max: Decoder.i64(1) }.Decoder))?
	show!("missing name", db.query_one!("SELECT id FROM events WHERE id = 1", decode_event))?
	show!("missing index", db.query_all!("SELECT id FROM events", Decoder.i64(1)))?

	show!("all", db.query_all!("SELECT id, payload FROM events WHERE id <> 2 ORDER BY id DESC", decode_event))?
	show!("all, bad row", db.query_all!("SELECT id, payload FROM events ORDER BY id", decode_event))?
	show!("all, none", db.query_all!("SELECT id, payload FROM events WHERE id > 9", decode_event))?
	show!("no statement, one", db.query_one!("", Decoder.row))?
	show!("no statement, all", db.query_all!(" /* nothing */ ", Decoder.row))?
	show!("no statement, a column", db.query_all!("", Decoder.i64("id")))?
	show!("two statements", db.query_all!("SELECT 1; SELECT 2", Decoder.row))?

	# Every early return above released its statement.
	show!("drop", db.execute!("DROP TABLE events"))
}

execute! : () => Try({}, _)
execute! = || {
	db = Sqlite.open_in_memory!()?
	db.execute!("CREATE TABLE t (x INTEGER)")?
	count! = || db.query_one!("SELECT COUNT(*) FROM t", Decoder.i64(0))

	# Refused before running: nothing is inserted.
	show!("returning", db.execute!("INSERT INTO t VALUES (1) RETURNING x"))?
	show!("select", db.execute!("SELECT x FROM t"))?
	show!("two statements", db.execute!("INSERT INTO t VALUES (1); INSERT INTO t VALUES (2)"))?
	show!("count", count!())?

	# Text with no statement does nothing.
	show!("empty", db.execute!(""))?
	show!("white space", db.execute!(" \n\t "))?
	show!("comment", db.execute!("-- nothing here"))?
	show!("trailing comment", db.execute!("INSERT INTO t VALUES (1); -- done"))?
	show!("empty with a value", db.execute!(Query.new("", [Null])))?
	show!("count", count!())?

	show!("script", db.execute_script!("INSERT INTO t VALUES (2); SELECT * FROM t; INSERT INTO t VALUES (3) RETURNING x;"))?
	show!("count", count!())?
	show!("empty script", db.execute_script!(""))?
	show!("comment script", db.execute_script!("/* nothing */ -- at all"))?
	# A script stops at the first failure; what ran before it stays.
	show!("failing script", db.execute_script!("INSERT INTO t VALUES (4); INSERT INTO missing VALUES (5); INSERT INTO t VALUES (6);"))?
	show!("count", count!())?
	show!("syntax", db.execute!("INSRT INTO t VALUES (1)"))
}

transaction! : () => Try({}, _)
transaction! = || {
	db = Sqlite.open_in_memory!()?
	db.execute!("CREATE TABLE t (x INTEGER NOT NULL)")?
	values! = || db.query_all!("SELECT x FROM t ORDER BY x", Decoder.i64("x"))
	insert! = |x| db.execute!("INSERT INTO t VALUES (${x})")

	committed = db.transaction!(
		|| {
			insert!(Integer(1))?
			insert!(Integer(2))?
			Ok("the body's value")
		},
	)
	show!("committed", committed)?
	show!("values", values!())?

	# The body's own error rolls back and is returned.
	own = db.transaction!(
		|| {
			insert!(Integer(3))?
			give_up(3)
		},
	)
	show!("own error", own)?
	show!("values", values!())?

	# So does a database error inside the body.
	failed = db.transaction!(
		|| {
			insert!(Integer(4))?
			insert!(Null)?
			Ok({})
		},
	)
	show!("database error", failed)?
	show!("values", values!())?

	# A transaction inside a transaction fails at BEGIN; the outer one goes on
	# and can still commit.
	nested = db.transaction!(
		|| {
			insert!(Integer(5))?
			inner = db.transaction!(|| insert!(Integer(6)))
			show!("inner", inner)?
			insert!(Integer(7))
		},
	)
	show!("nested", nested)?
	show!("values", values!())?

	db.close!()?
	show!("closed", db.transaction!(|| Ok({})))
}

give_up : I64 -> Try({}, [ChangedMyMind(I64)])
give_up = |n| Err(ChangedMyMind(n))

decoders! : () => Try({}, _)
decoders! = || {
	db = Sqlite.open_in_memory!()?
	db.execute_script!(
		\\CREATE TABLE t (id INTEGER PRIMARY KEY, i, r, s, b, flag);
		\\INSERT INTO t VALUES (1, 300, 1.5, 'text', x'00ff', 1);
		\\INSERT INTO t VALUES (2, NULL, NULL, NULL, NULL, 0);
		\\INSERT INTO t VALUES (3, 7, NULL, CAST(x'61c328' AS TEXT), x'', 2);
		,
	)?
	column! = |name, decoder| db.query_all!(Query.new("SELECT ${name} AS v, id FROM t ORDER BY id", []), decoder)
	one! = |id, decoder| db.query_one!("SELECT * FROM t WHERE id = ${Integer(id)}", decoder)

	show!("i64", column!("i", Decoder.i64("v").nullable()))?
	show!("f64", column!("r", Decoder.f64("v").nullable()))?
	show!("bytes", column!("b", Decoder.bytes("v").nullable()))?
	show!("bool", column!("flag", Decoder.bool("v")))?
	show!("str", one!(1, Decoder.str("s")))?
	show!("value", db.query_all!("SELECT s FROM t WHERE id < 3 ORDER BY id", Decoder.value(0)))?
	show!("value, bad utf8", one!(3, Decoder.value("s")))?
	show!("str, bad utf8", one!(3, Decoder.str("s")))?
	show!("str, bad utf8, nullable", one!(3, Decoder.str("s").nullable()))?
	show!("row", one!(1, Decoder.row))?
	show!("row, bad utf8", one!(3, Decoder.row))?
	show!("row, nullable", db.query_all!("SELECT i, r FROM t ORDER BY id", Decoder.row.nullable()))?

	# The error names the column and what it holds.
	show!("i64 of null", one!(2, Decoder.i64("i")))?
	show!("i64 of real", one!(1, Decoder.i64("r")))?
	show!("f64 of integer", one!(1, Decoder.f64("i")))?
	show!("str of bytes", one!(1, Decoder.str("b")))?
	show!("bytes of text", one!(1, Decoder.bytes("s")))?
	show!("bool of text", one!(1, Decoder.bool(3)))?

	# `nullable` over several columns: `Err(Null)` only when all are NULL.
	pair = { i: Decoder.i64("i"), r: Decoder.f64("r") }.Decoder.nullable()
	show!("pair, both", one!(1, pair))?
	show!("pair, neither", one!(2, pair))?
	show!("pair, one", one!(3, pair))?

	show!("map", one!(1, Decoder.i64("i").map(|n| n * 2)))?
	# A builtin's one-tag error has to be rebuilt before it joins the decoder's
	# other errors, here `value`'s and `i64`'s.
	# TODO(roc-lang/roc#12264): drop the `map_err` once that is fixed.
	narrow = {
		blob: Decoder.value("b"),
		byte: Decoder.i64("i").map_try(|n| n.to_u8_try().map_err(|OutOfRange| OutOfRange)),
	}.Decoder
	show!("map_try, ok", one!(3, narrow))?
	show!("map_try, own error", one!(1, narrow))?
	show!("map_try, decoder error", one!(2, narrow))?
	show!(
		"map_try, own tag",
		one!(
			1,
			Decoder.i64("i").map_try(
				|n| if n < 256 {
					Ok(n)
				} else {
					Err(TooBig(n))
				},
			),
		),
	)?

	# Two columns with one name: the name selects the first.
	show!("same name", db.query_one!("SELECT 1 AS n, 2 AS n", { name: Decoder.i64("n"), index: Decoder.i64(1) }.Decoder))?
	# A decoder constant shared by a list, a single row and a stream.
	show!("shared, all", db.query_all!("SELECT id, s AS payload FROM t WHERE id = 1", decode_event))?
	show!("shared, one", db.query_one!("SELECT id, s AS payload FROM t WHERE id = 1", decode_event))
}

params! : () => Try({}, _)
params! = || {
	db = Sqlite.open_in_memory!()?
	db.execute!("CREATE TABLE t (a, b)")?

	show!("too few", db.execute!(Query.new("INSERT INTO t VALUES (?, ?)", [Integer(1)])))?
	show!("too many", db.execute!(Query.new("INSERT INTO t VALUES (?, ?)", [Integer(1), Null, Null])))?
	show!("none wanted", db.query_all!(Query.new("SELECT a FROM t", [Integer(1)]), Decoder.row))?
	show!("none given", db.query_one!(Query.new("SELECT ?", []), Decoder.row))?
	show!("count", db.query_one!("SELECT COUNT(*) FROM t", Decoder.i64(0)))?

	# A numbered marker used twice is one parameter.
	show!("reused", db.query_one!(Query.new("SELECT ?1 AS x, ?1 AS y", [String("same")]), Decoder.row))?

	# Values keep their type, and text is never read as SQL.
	hostile = "'); DROP TABLE t; --"
	real = 2.5
	db.execute!("INSERT INTO t VALUES (${String(hostile)}, ${Bytes([0, 255])})")?
	db.execute!("INSERT INTO t VALUES (${Real(real)}, ${Null})")?
	db.execute!("INSERT INTO t VALUES (${String("")}, ${Bytes([])})")?
	show!("stored", db.query_all!("SELECT a, b FROM t ORDER BY rowid", { a: Decoder.value("a"), b: Decoder.value("b") }.Decoder))?

	# Strings and lists built at run time stay valid after being bound, and
	# binding the same ones again and again is fine.
	db.execute!("DELETE FROM t")?
	text = Str.repeat("x", 40)
	blob = List.repeat(7, 40)
	values = [String(text), Bytes(blob)]
	db.transaction!(
		|| {
			for _ in 0..<200 {
				db.execute!("INSERT INTO t VALUES (${String(text)}, ${Bytes(blob)})")?
				db.execute!(Query.new("INSERT INTO t VALUES (?, ?)", values))?
			}
			Ok({})
		},
	)?
	matching = db.query_one!(
		"SELECT COUNT(*) FROM t WHERE a = ${String(text)} AND b = ${Bytes(blob)}",
		Decoder.i64(0),
	)?
	show!("bound 400 times", matching)?
	show!("still intact", (text == Str.repeat("x", 40), blob == List.repeat(7, 40), values.len()))
}

errors! : () => Try({}, _)
errors! = || {
	db = Sqlite.open_in_memory!()?
	db.execute_script!(
		\\PRAGMA foreign_keys = ON;
		\\CREATE TABLE parent (id INTEGER PRIMARY KEY);
		\\CREATE TABLE child (
		\\    id INTEGER PRIMARY KEY,
		\\    email TEXT UNIQUE,
		\\    name TEXT NOT NULL,
		\\    age INTEGER CHECK (age >= 0),
		\\    parent INTEGER REFERENCES parent (id)
		\\);
		\\INSERT INTO parent VALUES (1);
		\\INSERT INTO child VALUES (1, 'a@example.org', 'a', 1, 1);
		,
	)?
	kind! = |query|
		match db.execute!(query) {
			Err(SqliteErr(Failed({ code: Constraint(kind), .. }))) => Str.inspect(kind)
			other => "not a constraint violation: ${Str.inspect(other)}"
		}

	show!("unique", kind!("INSERT INTO child VALUES (2, 'a@example.org', 'b', 1, 1)"))?
	show!("primary key", kind!("INSERT INTO child VALUES (1, 'b@example.org', 'b', 1, 1)"))?
	show!("foreign key", kind!("INSERT INTO child VALUES (2, 'b@example.org', 'b', 1, 99)"))?
	show!("not null", kind!("INSERT INTO child VALUES (2, 'b@example.org', NULL, 1, 1)"))?
	show!("check", kind!("INSERT INTO child VALUES (2, 'b@example.org', 'b', -1, 1)"))?
	show!("none", kind!("INSERT INTO child VALUES (2, 'b@example.org', 'b', 1, 1)"))?
	show!("full", db.execute!("INSERT INTO child VALUES (3, 'a@example.org', 'c', 1, 1)"))?

	# `Sqlite.Err` values compare with `==`.
	returns_rows = db.execute!("SELECT 1")
	show!("equal", returns_rows == Err(SqliteErr(ReturnsRows)))?
	show!("not equal", returns_rows == Err(SqliteErr(MultipleStatements)))?
	missing = db.query_one!("SELECT 1 AS a", Decoder.i64("b"))
	show!("equal column", missing == Err(SqliteErr(ColumnNotFound("b"))))?
	show!("not equal column", missing == Err(SqliteErr(ColumnNotFound(1))))?
	wrong_count = db.execute!(Query.new("INSERT INTO parent VALUES (?)", []))
	show!("equal count", wrong_count == Err(SqliteErr(WrongParamCount({ expected: 1, given: 0 }))))?
	syntax = db.execute!("nonsense")
	show!("equal failure", syntax == Err(SqliteErr(Failed({ code: Error, extended_code: 1, message: "near \"nonsense\": syntax error" }))))?
	show!("not equal failure", syntax == Err(SqliteErr(Failed({ code: Error, extended_code: 1, message: "" }))))?

	for result in [
		db.execute!("INSERT INTO child VALUES (4, 'a@example.org', 'd', 1, 1)"),
		db.execute!("SELECT 1"),
		db.execute!("SELECT 1; SELECT 2"),
		db.execute!(Query.new("INSERT INTO parent VALUES (?)", [Null, Null])),
	] {
		match result {
			Err(SqliteErr(err)) => Stdout.line!("to_str: ${err.to_str()}")?
			other => show!("no sqlite error", other)?
		}
	}
	for result in [db.query_all!("SELECT 1 AS a", Decoder.i64("b")), db.query_all!("SELECT 1 AS a", Decoder.i64(3))] {
		match result {
			Err(SqliteErr(err)) => Stdout.line!("to_str: ${err.to_str()}")?
			other => show!("no sqlite error", other)?
		}
	}
	Ok({})
}

close! : () => Try({}, _)
close! = || {
	db = events_db!()?
	events = db.rows("SELECT id, payload FROM events ORDER BY id", decode_event)

	# Closing while a stream is part way through: its next item is `Closed`,
	# and that is the last one.
	var $seen = 0
	for! item in events {
		$seen = $seen + 1
		match item {
			Ok(event) => {
				show!("row", event)?
				show!("close", db.close!())?
			}
			Err(BadRow(err)) => show!("bad row", err)?
			Err(SqliteErr(err)) => show!("sqlite error", err)?
			Err(Closed) => Stdout.line!("closed")?
		}
	}
	Stdout.line!("items: ${U64.to_str($seen)}")?

	show!("close again", db.close!())?
	show!("execute", db.execute!("SELECT 1"))?
	show!("execute, no statement", db.execute!(""))?
	show!("execute_script", db.execute_script!("SELECT 1"))?
	show!("query_one", db.query_one!("SELECT 1", Decoder.i64(0)))?
	show!("query_all", db.query_all!("SELECT 1", Decoder.i64(0)))?
	show!("transaction", db.transaction!(|| Ok({})))?
	# A new stream on the closed connection: `Closed` is its only item.
	drain!(events, "rows")?
	show!("inspect", db)?

	# A stream that outlives every other reference to its connection keeps
	# the connection open until the stream is released.
	orphan = orphan_stream!()?
	for! item in orphan {
		match item {
			Ok(event) if event.id == 3 => break
			Ok(event) => show!("orphan row", event)?
			Err(BadRow(err)) => show!("orphan bad row", err)?
			Err(SqliteErr(err)) => show!("orphan sqlite error", err)?
			Err(Closed) => Stdout.line!("orphan closed")?
		}
	}
	Stdout.line!("done")
}

orphan_stream! : () => Try(Stream(Try(Event, [SqliteErr(Sqlite.Err), Closed, BadRow(Sqlite.DecodeErr)])), _)
orphan_stream! = || {
	db = events_db!()?
	Ok(db.rows("SELECT id, payload FROM events ORDER BY id", decode_event))
}

files! : Path => Try({}, _)
files! = |directory| {
	path = Path.join(directory, "app.db")
	count! = |db| db.query_one!("SELECT COUNT(*) FROM t", Decoder.i64(0))
	code! = |result|
		match result {
			Err(SqliteErr(Failed({ code, .. }))) => Str.inspect(code)
			other => "no failure: ${Str.inspect(other)}"
		}

	# Only the default mode creates a missing file.
	show!("read-write, missing", code!(Sqlite.open!(path, { mode: ReadWrite }).map_ok(|_| {})))?
	show!("read-only, missing", code!(Sqlite.open!(path, { mode: ReadOnly }).map_ok(|_| {})))?
	show!("created by a failed open", Path.exists!(path)?)?

	writer = Sqlite.open!(path, {})?
	writer.execute_script!("CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);")?
	show!("created", Path.exists!(path)?)?

	reader = Sqlite.open!(path, { mode: ReadOnly })?
	show!("read-only reads", count!(reader))?
	show!("read-only write", code!(reader.execute!("INSERT INTO t VALUES (2)")))?
	show!("read-only script", code!(reader.execute_script!("DELETE FROM t")))?

	# Two opens of one path are two connections: the second does not see the
	# first one's open transaction, and cannot write while it holds the lock.
	busy_timeout = Duration.zero
	other = Sqlite.open!(path, { mode: ReadWrite, busy_timeout })?
	writer.execute!("BEGIN IMMEDIATE")?
	writer.execute!("INSERT INTO t VALUES (2)")?
	show!("inside", count!(writer))?
	show!("outside", count!(other))?
	show!("locked", code!(other.execute!("INSERT INTO t VALUES (3)")))?
	# Closing the other connection leaves the transaction alone.
	other.close!()?
	writer.execute!("COMMIT")?
	show!("after commit", count!(reader))?

	# In-memory databases are private, however they are opened: `":memory:"`
	# is not a file two connections could share.
	first = Sqlite.open_in_memory!()?
	second = Sqlite.open!(":memory:", {})?
	third = Sqlite.open!(":memory:", {})?
	first.execute!("CREATE TABLE only_in_first (x)")?
	second.execute!("CREATE TABLE only_in_second (x)")?
	show!("first sees second", code!(first.execute!("INSERT INTO only_in_second VALUES (1)")))?
	show!("second sees first", code!(second.execute!("INSERT INTO only_in_first VALUES (1)")))?
	show!("third sees second", code!(third.execute!("INSERT INTO only_in_second VALUES (1)")))
}

## Function-value and method forms beside another error: the error rows have
## to be open for this to check. They are closed at the host boundary by
## design, and every `Sqlite` function rebuilds its error into an open row.
error_rows! : U64 => Try({}, _)
error_rows! = |args_len| {
	if args_len > 1 {
		return Err(UnexpectedArguments)
	}

	open! = Sqlite.open!
	open_in_memory! = Sqlite.open_in_memory!
	db_execute! = Sqlite.Db.execute!
	db_execute_script! = Sqlite.Db.execute_script!
	db_close! = Sqlite.Db.close!

	db = open!(":memory:", {})?
	other = open_in_memory!()?
	db_execute_script!(db, "CREATE TABLE t (x INTEGER); INSERT INTO t VALUES (1);")?
	db_execute!(db, "INSERT INTO t VALUES (2)")?
	one = db.query_one!("SELECT MAX(x) FROM t", Decoder.i64(0))?
	all = db.query_all!("SELECT x FROM t ORDER BY x", Decoder.i64("x"))?
	db.transaction!(|| db.execute!("DELETE FROM t"))?
	db.execute_script!("DROP TABLE t")?
	db_close!(db)?
	other.close!()?

	show!("error rows", (one, all))
}
