import Host
import Path
import IOErr

## Read file bytes incrementally and seek within files.
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
	Reader :: { host : Host.FileReader }.{

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
}
