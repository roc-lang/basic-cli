import Host
import Path
import IOErr exposing [IOErr]

## Read file bytes incrementally and seek within files.
##
## Whole-file operations and filesystem metadata are available on [`Path`](Path).
File :: [].{

	## A byte offset from the start, current logical position, or end of a file.
	SeekFrom : [Start(U64), Current(I64), End(I64)]

	## Represents a buffered file reader.
	##
	## The file is automatically closed when the last reference to the reader is
	## dropped. It wraps an opaque host-side `BufReader<File>` handle.
	## Aliases share one cursor, including bytes buffered by line or binary reads.
	Reader :: { host : Host.FileReader }.{

		## Render the reader without exposing its host handle.
		to_inspect : Reader -> Str
		to_inspect = |_| "File.Reader(<opaque>)"

		## Read bytes up to and including the next newline from this buffered reader.
		##
		## Returns an empty list at EOF.
		read_line! : Reader => Try(List(U8), _)
		read_line! = |reader|
			Host.file_read_line!(reader.host)
				.map_err(|FileErr(err)| FileErr(err))

		## Read at most `max_bytes` bytes. Short reads are valid, even before EOF.
		## For a positive maximum, an empty list means EOF. Zero performs no I/O.
		## Returned bytes remain valid after later reads or seeks.
		read_up_to! : Reader, U64 => Try(List(U8), [FileErr(IOErr)])
		read_up_to! = |reader, max_bytes|
			Host.file_read_up_to!(reader.host, max_bytes)
				.map_err(|FileErr(err)| FileErr(err))

		## Read exactly `count` bytes, or report `FileUnexpectedEOF`.
		## Zero succeeds without I/O. Errors may consume bytes; partial data is
		## not returned and the cursor is not restored.
		read_exactly! : Reader, U64 => Try(List(U8), [FileErr(IOErr), FileUnexpectedEOF])
		read_exactly! = |reader, count|
			match Host.file_read_exactly!(reader.host, count) {
				Ok(bytes) => Ok(bytes)
				Err(FileUnexpectedEOF) => Err(FileUnexpectedEOF)
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

		## Lazily read nonempty chunks of at most `max_bytes` from this reader.
		## Zero is rejected immediately with InvalidChunkSize. Construction does
		## no I/O; each pull reads from the current shared cursor. Chunk boundaries
		## do not correspond to records, newlines, or text encoding boundaries.
		## EOF ends the stream; a read error yields one Err item, then ends.
		## Follow the returned continuation when pulling. To resume after EOF
		## and a seek, create a new stream. Retained chunks remain valid.
		## The stream keeps the file open while it retains a reader. Its terminal
		## continuation holds no reader. Process chunks individually to bound memory;
		## Stream.collect! accumulates every chunk and does not propagate Err items.
		chunks : Reader, U64 -> Try(Stream(Try(List(U8), [FileErr(IOErr)])), [InvalidChunkSize])
		chunks = |reader, max_bytes|
			if max_bytes == 0 {
				Err(InvalidChunkSize)
			} else {
				# TODO(https://github.com/roc-lang/roc/issues/11691): requires Stream.custom.
				# Keep the reader in the state, not the callback capture, so Finished
				# can release it even when the terminal continuation is retained.
				Ok(
					Stream.custom(
						Reading(reader),
						Unknown,
						|state|
							match state {
								Finished => Err(NoMore)
								Reading(current) =>
									match read_up_to!(current, max_bytes) {
										Ok(bytes) if bytes.is_empty() => Err(NoMore)
										Ok(bytes) => Ok((Ok(bytes), Reading(current)))
										Err(FileErr(err)) => Ok((Err(FileErr(err)), Finished))
									}
								},
					),
				)
			}
	}

	## Open a file for buffered reading using the default buffer capacity.
	##
	## Failing to open reports the path, using the same `PathErr` as the
	## whole-file operations so both combine in one error type.
	##
	## ```roc
	## reader = File.open_reader!("LICENSE")?
	## line = reader.read_line!()?
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
