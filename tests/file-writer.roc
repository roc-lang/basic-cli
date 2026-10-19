## Exercise `File.Writer`: the three write modes, buffering and flushing,
## `write_stream!`, `File.with_writer!` and the errors each one returns.
## scripts/test.py runs every mode in a temporary working directory and checks
## that no writer handle is left open.
app [main!] { pf: platform "../platform/main.roc" }

import pf.File
import pf.IOErr
import pf.OsStr
import pf.Path
import pf.Stdin
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	mode = match args {
		[arg, ..] => OsStr.display(arg)
		[] => ""
	}

	match mode {
		"modes" => modes!()
		"buffering" => buffering!()
		"streams" => streams!()
		"with-writer" => with_writer!()
		"error-rows" => error_rows!(args.len())
		"stdin" => stdin!()
		_ => Err(UnknownMode(mode))
	}
}

show! : Str, Path => Try({}, _)
show! = |label, path|
	Stdout.line!("${label}: ${Str.inspect(path.read_utf8!()?)}")

## `Truncate`, `Append` and `RequireNew`, and what each does to existing data.
modes! : () => Try({}, _)
modes! = || {
	path : Path
	path = "modes.txt"

	File.with_writer!(path, RequireNew, {}, |writer| writer.write_utf8!("new\n"))?
	show!("RequireNew on a free path", path)?

	# `AlreadyExists` if anything is at the path; the file is left alone.
	again = File.open_writer!(path, RequireNew, {}).map_ok(|_| {})
	expect again == Err(PathErr(AlreadyExists, path))
	Stdout.line!("RequireNew on a file: ${Str.inspect(again)}")?
	scoped = File.with_writer!(path, RequireNew, {}, |writer| writer.write_utf8!("replaced\n"))
	expect scoped == Err(PathErr(AlreadyExists, path))
	directory : Path
	directory = "a-directory"
	directory.create_dir!()?
	on_directory = File.open_writer!(directory, RequireNew, {}).map_ok(|_| {})
	expect on_directory == Err(PathErr(AlreadyExists, directory))
	Stdout.line!("RequireNew on a directory: ${Str.inspect(on_directory)}")?
	show!("after the refused opens", path)?

	File.with_writer!(path, Append, {}, |writer| writer.write_bytes!("appended\n".to_utf8()))?
	show!("Append to a file", path)?

	File.with_writer!(path, Truncate, {}, |writer| writer.write_utf8!("truncated\n"))?
	show!("Truncate a file", path)?

	# Opening is all it takes to empty the file.
	_ = File.open_writer!(path, Truncate, {})?
	show!("Truncate without writing", path)?

	created : Path
	created = "created-by-append.txt"
	File.with_writer!(created, Append, {}, |writer| writer.write_utf8!("first\n"))?
	File.with_writer!(created, Append, {}, |writer| writer.write_utf8!("second\n"))?
	show!("Append creates the file", created)?

	fresh : Path
	fresh = "created-by-truncate.txt"
	File.with_writer!(fresh, Truncate, {}, |_writer| Ok({}))?
	show!("Truncate creates the file", fresh)?

	# A failed open names the path, in every mode.
	missing : Path
	missing = "no-such-directory/file.txt"
	for write_mode in [Truncate, Append, RequireNew] {
		result = File.open_writer!(missing, write_mode, {}).map_ok(|_| {})
		expect result == Err(PathErr(NotFound, missing))
		Stdout.line!("missing parent, ${Str.inspect(write_mode)}: ${Str.inspect(result)}")?
	}
	on_dir = File.open_writer!(directory, Truncate, {}).map_ok(|_| {})
	expect on_dir == Err(PathErr(IsADirectory, directory))
	Stdout.line!("Truncate on a directory: ${Str.inspect(on_dir)}")
}

## Bytes stay in the host's buffer until a flush or the last release.
buffering! : () => Try({}, _)
buffering! = || {
	path : Path
	path = "buffered.txt"

	writer = File.open_writer!(path, Truncate, {})?
	Stdout.line!("inspect: ${Str.inspect(writer)}")?
	writer.write_utf8!("one,")?
	# A copy shares the file and the buffer, so writes keep their order.
	copy = writer
	copy.write_bytes!("two,".to_utf8())?
	writer.write_utf8!("")?
	writer.write_utf8!("three")?
	show!("before flush!", path)?
	copy.flush!()?
	show!("after flush!", path)?
	writer.flush!()?
	show!("after a second flush!", path)?

	# A write larger than the buffer arrives whole and in order.
	large = List.repeat('x', 300_000)
	writer.write_utf8!("|")?
	writer.write_bytes!(large)?
	writer.write_utf8!("|")?
	writer.flush!()?
	contents = path.read_bytes!()?
	expect contents.len() == 300_015
	expect contents.drop_first(14).drop_last(1) == large
	Stdout.line!("after a large write: ${contents.len().to_str()} bytes, ending ${Str.inspect(contents.take_last(2))}")?

	# No flush and no close: the last release writes what is buffered.
	dropped : Path
	dropped = "dropped.txt"
	write_and_drop!(dropped, False)?
	show!("dropped without flush!", dropped)?
	match write_and_drop!(dropped, True) {
		Err(LeftEarly) => {}
		other => {
			return Err(ExpectedLeftEarly(other))
		}
	}
	show!("dropped by an early return", dropped)?

	# The writer above is still open; a second one appends after its data.
	File.open_writer!(path, Append, {})?.write_utf8!("appended")?
	appended = path.read_bytes!()?
	Stdout.line!("appended through a temporary writer: ${appended.len().to_str()} bytes, ending ${Str.inspect(appended.take_last(2))}")
}

write_and_drop! : Path, Bool => Try({}, _)
write_and_drop! = |path, early| {
	writer = File.open_writer!(path, Append, {})?
	aliases = [writer, writer]
	for alias in aliases {
		alias.write_utf8!("kept ")?
	}
	if early {
		return Err(LeftEarly)
	}
	Ok({})
}

## `write_stream!` writes every chunk before the first `Err` item and wraps
## that item in `SourceErr`.
streams! : () => Try({}, _)
streams! = || {
	path : Path
	path = "stream.txt"
	chunk = |text| Ok(text.to_utf8())

	whole = File.with_writer!(
		path,
		Truncate,
		{},
		|writer| writer.write_stream!(Stream.from_iter([chunk("a"), chunk(""), chunk("bc")].iter())),
	)
	Stdout.line!("stream without an error: ${Str.inspect(whole)}")?
	show!("  wrote", path)?

	broken = [chunk("first,"), chunk("second"), Err(Boom("after two chunks")), chunk(",never")]
	failed = File.with_writer!(
		path,
		Truncate,
		{},
		|writer| writer.write_stream!(Stream.from_iter(broken.iter())),
	)
	expect failed == Err(SourceErr(Boom("after two chunks")))
	Stdout.line!("stream with an error: ${Str.inspect(failed)}")?
	show!("  wrote", path)?

	# A file read in chunks is a source too; its errors would be
	# `SourceErr(FileErr(_))`, beside the writer's own `FileErr(_)`.
	source : Path
	source = "source.bin"
	# 200,000 bytes: more than three chunks, and not a multiple of a chunk.
	bytes = List.repeat("0123456789abcdefghij".to_utf8(), 10_000).join()
	source.write_bytes!(bytes)?
	copy : Path
	copy = "copy.bin"
	reader = File.open_reader!(source)?
	copied = File.with_writer!(copy, RequireNew, {}, |writer| writer.write_stream!(reader.chunks()))
	match copied {
		Ok({}) => {}
		Err(SourceErr(FileErr(err))) => {
			return Err(ReadFailed(err))
		}
		Err(FileErr(err)) => {
			return Err(WriteFailed(err))
		}
		Err(PathErr(err, failed_path)) => {
			return Err(PathErr(err, failed_path))
		}
	}
	copied_bytes = copy.read_bytes!()?
	Stdout.line!("copied ${copied_bytes.len().to_str()} bytes, equal: ${Str.inspect(copied_bytes == bytes)}")?

	# Without `with_writer!` the same call works on a writer directly.
	writer = File.open_writer!(path, Append, {})?
	direct = writer.write_stream!(Stream.from_iter([chunk("|x"), Err(Stopped), chunk("y")].iter()))
	expect direct == Err(SourceErr(Stopped))
	writer.flush!()?
	Stdout.line!("direct write_stream!: ${Str.inspect(direct)}")?
	show!("  wrote", path)
}

## `File.with_writer!` flushes after the callback and returns the callback's
## own value or error.
with_writer! : () => Try({}, _)
with_writer! = || {
	path : Path
	path = "scoped.txt"

	value = File.with_writer!(
		path,
		Truncate,
		{},
		|writer| {
			writer.write_utf8!("written")?
			Ok(42.U64)
		},
	)?
	Stdout.line!("callback value: ${value.to_str()}")?
	show!("  flushed", path)?

	# The callback's error comes back as it is, and what it wrote is flushed.
	failed : Try({}, [Refused(Str), PathErr(IOErr, Path), FileErr(IOErr)])
	failed = File.with_writer!(
		path,
		Truncate,
		{},
		|writer| {
			writer.write_utf8!("partial")?
			Err(Refused("by the callback"))
		},
	)
	expect failed == Err(Refused("by the callback"))
	Stdout.line!("callback error: ${Str.inspect(failed)}")?
	show!("  flushed", path)?

	# A writer that outlives the callback stays open and usable.
	kept = File.with_writer!(path, Append, {}, |writer| Ok(writer))?
	kept.write_utf8!(" and more")?
	kept.flush!()?
	show!("writer kept by the callback", path)?

	only_file_errors!(path)?
	show!("annotated with PathErr and FileErr only", path)
}

## The error of a `with_writer!` whose callback only writes is exactly this.
only_file_errors! : Path => Try({}, [PathErr(IOErr, Path), FileErr(IOErr)])
only_file_errors! = |path|
	File.with_writer!(
		path,
		Truncate,
		{},
		|writer| {
			writer.write_utf8!("name,total\n")?
			writer.write_bytes!("apples,3\n".to_utf8())?
			writer.flush!()
		},
	)

## Every function as a method, a qualified call and a function value, beside
## an error of the caller's, so each error row has to be open.
error_rows! : U64 => Try({}, _)
error_rows! = |arg_count| {
	if arg_count > 1 {
		return Err(UnexpectedArguments)
	}
	path : Path
	path = "rows.txt"

	open! = File.open_writer!
	write_utf8! = File.Writer.write_utf8!
	write_bytes! = File.Writer.write_bytes!
	flush! = File.Writer.flush!

	writer = open!(path, Truncate, {})?
	write_utf8!(writer, "value,")?
	write_bytes!(writer, "value,".to_utf8())?
	flush!(writer)?
	File.Writer.write_utf8!(writer, "qualified,")?
	File.Writer.write_bytes!(writer, "qualified,".to_utf8())?
	File.Writer.flush!(writer)?
	writer.write_utf8!("method,")?
	writer.write_bytes!("method".to_utf8())?
	writer.flush!()?
	show!("error rows", path)
}

## `Stdin.chunks()` is a chunk stream like any other.
stdin! : () => Try({}, _)
stdin! = || {
	path : Path
	path = "stdin.bin"
	result = File.with_writer!(path, Truncate, {}, |writer| writer.write_stream!(Stdin.chunks()))
	match result {
		Ok({}) => {}
		Err(SourceErr(Interrupted)) => {
			return Err(Interrupted)
		}
		Err(SourceErr(StdinErr(err))) => {
			return Err(StdinErr(err))
		}
		Err(FileErr(err)) => {
			return Err(FileErr(err))
		}
		Err(PathErr(err, failed_path)) => {
			return Err(PathErr(err, failed_path))
		}
	}
	Stdout.line!("copied from stdin: ${Str.inspect(path.read_bytes!()?)}")
}
