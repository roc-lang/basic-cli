import Host
import Resource
import Path
import IOErr

## Read file bytes incrementally, seek within files, and write to a file
## piece by piece.
##
## Whole-file operations and filesystem metadata are available on [`Path`](Path).
File :: [].{

	## A byte offset from the start, current logical position, or end of a file.
	SeekFrom : [Start(U64), Current(I64), End(I64)]

	## A buffered file reader.
	##
	## The file is closed when the last reference to the reader is released.
	## Copies of a reader share one cursor and one buffer, so every read,
	## whether of lines, delimited bytes or binary data, continues where the
	## previous one stopped.
	##
	## Every read ends the same way: once all data has been returned, the next
	## read is `Err(EndOfInput)`. An empty `Ok` is real data, such as an empty
	## line. A read may be repeated after `EndOfInput`; if the file has grown
	## it returns the new data.
	Reader :: { host : Resource.FileReader }.{

		# A tag union that crosses the host boundary is closed by design, so
		# every method below rebuilds the error it forwards from the host. That
		# gives callers an open union, which `?` can combine with other error
		# types however the method is called.

		## Render the reader without exposing its host handle.
		to_inspect : Reader -> Str
		to_inspect = |_| "File.Reader(<opaque>)"

		## Read at most `max_bytes` bytes. Short reads are valid, even before
		## the end of the file. Asking for zero bytes performs no I/O and
		## returns `Ok([])`; otherwise the result is never empty, and the end
		## of the file is `Err(EndOfInput)`.
		## Returned bytes remain valid after later reads or seeks.
		read_up_to! : Reader, U64 => Try(List(U8), [EndOfInput, FileErr(IOErr)])
		read_up_to! = |reader, max_bytes|
			match Host.file_read_up_to!(reader.host, max_bytes) {
				Ok(bytes) => Ok(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(FileErr(err)) => Err(FileErr(err))
			}

		## Read exactly `count` bytes, or report `UnexpectedEndOfInput`.
		## Zero succeeds without I/O. Errors may consume bytes; partial data is
		## not returned and the cursor is not restored.
		read_exactly! : Reader, U64 => Try(List(U8), [UnexpectedEndOfInput, FileErr(IOErr)])
		read_exactly! = |reader, count|
			match Host.file_read_exactly!(reader.host, count) {
				Ok(bytes) => Ok(bytes)
				Err(UnexpectedEndOfInput) => Err(UnexpectedEndOfInput)
				Err(FileErr(err)) => Err(FileErr(err))
			}

		## Read bytes through and including the next `delimiter`.
		##
		## If the file ends first, the bytes before the end are returned without
		## a delimiter, and the read after that is `Err(EndOfInput)`. So the
		## result is never empty, and its last byte shows whether the delimiter
		## arrived: to follow a growing file line by line, use
		## `reader.read_until!('\n')` rather than [read_line!].
		read_until! : Reader, U8 => Try(List(U8), [EndOfInput, FileErr(IOErr)])
		read_until! = |reader, delimiter|
			match Host.file_read_until!(reader.host, delimiter) {
				Ok(bytes) => Ok(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(FileErr(err)) => Err(FileErr(err))
			}

		## Read a line of text.
		##
		## A line ends at `\n`. The terminator is not returned, and one `\r`
		## before it is removed. A file that ends without a `\n` still yields
		## its last line; after that the result is `Err(EndOfInput)`. An empty
		## line is `Ok("")`. Lines have no length limit.
		##
		## A line that is not valid UTF-8 is consumed and reported as `BadUtf8`;
		## the next call reads the line after it. For the bytes of a line, use
		## `reader.read_until!('\n')`.
		read_line! : Reader => Try(Str, [EndOfInput, BadUtf8({ problem : Str.Utf8Problem, index : U64 }), FileErr(IOErr)])
		read_line! = |reader|
			match Host.file_read_line!(reader.host) {
				Ok(bytes) => Str.from_utf8(bytes)
				Err(EndOfInput) => Err(EndOfInput)
				Err(FileErr(err)) => Err(FileErr(err))
			}

		## Return the byte position of the next read, accounting for buffered bytes.
		position! : Reader => Try(U64, [FileErr(IOErr)])
		position! = |reader|
			Host.file_reader_position!(reader.host)
				.map_err(|FileErr(err)| FileErr(err))

		## Move the shared cursor and return its new absolute byte position.
		## Seeking past EOF does not extend the file. Invalid offsets and sources
		## that cannot seek report FileErr. A failed seek need not restore the cursor.
		## Aliases of this reader observe the same cursor.
		seek! : Reader, SeekFrom => Try(U64, [FileErr(IOErr)])
		seek! = |reader, from|
			Host.file_reader_seek!(reader.host, from)
				.map_err(|FileErr(err)| FileErr(err))

		## Lazily read this reader a line at a time, as [read_line!] does.
		##
		## Building the stream reads nothing. The stream ends at the end of the
		## file. A `BadUtf8` item concerns one line, and the stream continues
		## with the next. A `FileErr` item is the last one; the reader stays
		## usable and a new stream may be started.
		##
		## Each item is one read from the shared cursor and the stream holds no
		## data of its own, so it can be mixed with [seek!], [position!] and
		## the other reads, and leaving the loop early loses nothing.
		##
		## ```roc
		## for! item in reader.lines() {
		##     match item {
		##         Ok(line) => Stdout.line!(line)?
		##         Err(BadUtf8(_)) => {}
		##         Err(FileErr(err)) => { return Err(FileErr(err)) }
		##     }
		## }
		## ```
		##
		## The stream keeps the file open until it has finished or is released.
		lines : Reader -> Stream(Try(Str, [BadUtf8({ problem : Str.Utf8Problem, index : U64 }), FileErr(IOErr)]))
		lines = |reader|
			# Keep the reader in the state, not the callback capture, so Finished
			# can release it even when the terminal continuation is retained.
			Stream.custom(
				Reading(reader),
				Unknown,
				|state|
					match state {
						Finished => Err(NoMore)
						Reading(current) =>
							match read_line!(current) {
								Ok(text) => Ok((Ok(text), Reading(current)))
								Err(EndOfInput) => Err(NoMore)
								Err(BadUtf8(problem)) => Ok((Err(BadUtf8(problem)), Reading(current)))
								Err(FileErr(err)) => Ok((Err(FileErr(err)), Finished))
							}
					},
			)

		## Lazily read this reader as non-empty chunks of at most 64 KiB.
		## Chunk boundaries do not correspond to records, newlines, or text
		## encoding boundaries. For a chosen size, call [read_up_to!] in a loop.
		##
		## Building the stream reads nothing; each item is one read from the
		## shared cursor. The stream ends at the end of the file. A `FileErr`
		## item is the last one; the reader stays usable and a new stream may be
		## started, for example after a [seek!]. Retained chunks remain valid.
		##
		## ```roc
		## for! item in reader.chunks() {
		##     bytes = item?
		##     $total = $total + bytes.len()
		## }
		## ```
		##
		## The stream keeps the file open until it has finished or is released.
		## Process chunks individually to bound memory; `Stream.collect!`
		## accumulates every chunk.
		chunks : Reader -> Stream(Try(List(U8), [FileErr(IOErr)]))
		chunks = |reader|
			# Keep the reader in the state, not the callback capture, so Finished
			# can release it even when the terminal continuation is retained.
			Stream.custom(
				Reading(reader),
				Unknown,
				|state|
					match state {
						Finished => Err(NoMore)
						Reading(current) =>
							match read_up_to!(current, 65_536) {
								Ok(bytes) => Ok((Ok(bytes), Reading(current)))
								Err(EndOfInput) => Err(NoMore)
								Err(FileErr(err)) => Ok((Err(FileErr(err)), Finished))
							}
					},
			)
	}

	## What opening a [Writer] does to the file at the path.
	##
	## - `Truncate` creates the file, or empties it if it exists.
	## - `Append` creates the file if it is missing and keeps what it holds;
	##   every write goes to the end.
	## - `RequireNew` creates the file and fails with `AlreadyExists` if
	##   anything is at the path.
	WriteMode : [Truncate, Append, RequireNew]

	## Explicit access policies apply only when a regular file is newly created.
	## OwnerOnly grants the owner read/write and others no access; PublicRead
	## additionally grants everyone read. Both replace inherited ACL grants.
	## Existing files keep their permissions. Use RequireNew with OwnerOnly for
	## secrets. Filesystems that cannot enforce a policy return Unsupported.
	WriterOptions := { create_permissions : [Default, OwnerOnly, PublicRead] ?? Default }

	## A buffered file writer.
	##
	## Written bytes are held in a buffer in the host and reach the operating
	## system when the buffer fills and on [flush!]. A write accepts all of
	## its bytes or fails. Copies of a writer share one file and one buffer.
	##
	## There is no `close!`: the file is closed when the last reference to the
	## writer is released. Bytes still buffered then are written, but a
	## failure to write them cannot be reported, so call [flush!] after the
	## last write, or use [File.with_writer!], which does it for you.
	Writer :: { host : Resource.FileWriter }.{

		# A tag union that crosses the host boundary is closed by design, so
		# every method below rebuilds the error it forwards from the host. That
		# gives callers an open union, which `?` can combine with other error
		# types however the method is called.

		## Render the writer without exposing its host handle.
		to_inspect : Writer -> Str
		to_inspect = |_| "File.Writer(<opaque>)"

		## Write all of `bytes`, to the buffer or to the file.
		write_bytes! : Writer, List(U8) => Try({}, [FileErr(IOErr)])
		write_bytes! = |writer, bytes|
			Host.file_writer_write_bytes!(writer.host, bytes)
				.map_err(|FileErr(err)| FileErr(err))

		## Write all of `text` as UTF-8, to the buffer or to the file. No line
		## ending is added.
		write_utf8! : Writer, Str => Try({}, [FileErr(IOErr)])
		write_utf8! = |writer, text|
			Host.file_writer_write_utf8!(writer.host, text)
				.map_err(|FileErr(err)| FileErr(err))

		## Write each chunk of a stream as it arrives, holding one chunk in
		## memory at a time.
		##
		## Stops at the first `Err` item, which is returned as `SourceErr`; the
		## chunks before it have been written. A failed write is `FileErr`.
		## Nothing is flushed at the end.
		##
		## Any stream of byte chunks will do: `reader.chunks()`,
		## `Stdin.chunks()`, the `response.chunks()` of an
		## [Http.send_streaming!](Http.send_streaming!) response, or a stream
		## mapped from one of them.
		##
		## ```roc
		## reader = File.open_reader!(source)?
		## File.with_writer!(destination, Truncate, {}, |writer|
		##     writer.write_stream!(reader.chunks().map(|chunk| chunk.map_ok(redact))))?
		## ```
		write_stream! : Writer, Stream(Try(List(U8), err)) => Try({}, [FileErr(IOErr), SourceErr(err)])
		write_stream! = |writer, stream| {
			for! item in stream {
				match item {
					Ok(bytes) => write_bytes!(writer, bytes)?
					Err(err) => {
						return Err(SourceErr(err))
					}
				}
			}
			Ok({})
		}

		## Hand every buffered byte to the operating system.
		##
		## This is the call that reports whether the bytes written so far
		## reached the file. It does not force them to the storage device.
		flush! : Writer => Try({}, [FileErr(IOErr)])
		flush! = |writer|
			Host.file_writer_flush!(writer.host)
				.map_err(|FileErr(err)| FileErr(err))
	}

	## Open a file for buffered reading using the default buffer capacity.
	##
	## Failing to open reports the path, using the same `PathErr` as the
	## whole-file operations so both combine in one error type.
	##
	## ```roc
	## reader = File.open_reader!("LICENSE")?
	## first_line = reader.read_line!()?
	## ```
	open_reader! = |path|
		Host.file_open_reader!(Path.to_raw(path), 0)
			.map_ok(|reader| Reader.{ host: reader })
			.map_err(|FileErr(err)| PathErr(err, path))

	## Open a file for buffered reading using a specific buffer capacity.
	open_reader_with_capacity! = |path, capacity|
		Host.file_open_reader!(Path.to_raw(path), capacity)
			.map_ok(|reader| Reader.{ host: reader })
			.map_err(|FileErr(err)| PathErr(err, path))

	## Open a file for buffered writing. The [WriteMode] decides whether
	## existing data survives, so it has no default.
	##
	## Failing to open reports the path, as [File.open_reader!] does.
	##
	## Prefer [File.with_writer!]: with a writer opened here, a `?` on a write
	## returns before the final [flush!](File.Writer.flush!), and the failure
	## of the flush that happens on release is not reported.
	##
	## ```roc
	## log = File.open_writer!("events.log", Append, {})?
	## log.write_utf8!("started\n")?
	## log.flush!()?
	## ```
	open_writer! : Path, WriteMode, WriterOptions => Try(Writer, [PathErr(IOErr, Path)])
	open_writer! = |path, mode, options|
		Host.file_open_writer!(Path.to_raw(path), mode, options.create_permissions)
			.map_ok(|writer| Writer.{ host: writer })
			.map_err(|FileErr(err)| PathErr(err, path))

	## Open a file for writing, run `callback` with the writer, then flush,
	## whether the callback succeeded or failed.
	##
	## If the callback fails, its error is returned unchanged and a failure of
	## the flush is discarded. If only the flush fails, that is the `FileErr`.
	## The file is closed once no reference to the writer remains, normally
	## when this function returns.
	##
	## ```roc
	## File.with_writer!("report.csv", Truncate, {}, |writer| {
	##     writer.write_utf8!("name,total\n")?
	##     for row in rows {
	##         writer.write_utf8!("${row.name},${row.total.to_str()}\n")?
	##     }
	##     Ok({})
	## })?
	## ```
	with_writer! :
		Path, WriteMode, WriterOptions, (Writer => Try(a, [PathErr(IOErr, Path), FileErr(IOErr), ..errs])) => Try(a, [PathErr(IOErr, Path), FileErr(IOErr), ..errs])
	with_writer! = |path, mode, options, callback!| {
		writer = open_writer!(path, mode, options)?
		match callback!(writer) {
			Ok(value) => {
				writer.flush!()?
				Ok(value)
			}
			Err(err) => {
				_ = writer.flush!()
				Err(err)
			}
		}
	}
}
