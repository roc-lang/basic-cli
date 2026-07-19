## Read a file incrementally with a buffer instead of loading it all at once.
##
## This can be useful to process large files without using a lot of RAM or
## requiring the user to wait until the complete file is processed when they
## only wanted to look at the first page.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.File
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {

	reader : File.Reader
	reader = File.open_reader!("LICENSE")?

	read_summary : ReadSummary
	read_summary = process_line!(reader, { lines_read: 0, bytes_read: 0 })?

	Stdout.line!("Done reading file: ${Str.inspect(read_summary)}")?

	Ok({})
}

ReadSummary := { lines_read : U64, bytes_read : U64 }

## Count the number of lines and the number of bytes read.
process_line! : File.Reader, ReadSummary => Try(ReadSummary, _)
process_line! = |reader, { lines_read, bytes_read }|
	match reader.read_line!() {
		Ok(bytes) if bytes.len() == 0 =>
			Ok({ lines_read, bytes_read })

		Ok(bytes) =>
			process_line!(
				reader,
				{
					lines_read: lines_read + 1,
					bytes_read: bytes_read + bytes.len(),
				},
			)

		Err(err) => Err(err)
	}
