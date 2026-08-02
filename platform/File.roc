import Host
import Path

## Open files for incremental, buffered reading.
##
## Whole-file operations and filesystem metadata are available on [`Path`](Path).
File :: [].{

	## Represents a buffered file reader.
	##
	## The file is automatically closed when the last reference to the reader is
	## dropped. It wraps an opaque host-side `BufReader<File>` handle.
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
