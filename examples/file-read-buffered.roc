## Read a file incrementally with a buffer instead of loading it all at once.
##
## This can be useful to process large files without using a lot of RAM or
## requiring the user to wait until the complete file is processed when they
## only wanted to look at the first page.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.File
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	reader : File.Reader
	reader = File.open_reader!("LICENSE")?

	read_summary = summarize!(reader)?

	Stdout.line!("Done reading file: ${Str.inspect(read_summary)}")?

	Ok({})
}

ReadSummary := { lines_read : U64, longest_line_bytes : U64 }

## Count the lines and find the length of the longest one, holding only one
## line in memory at a time.
summarize! : File.Reader => Try(ReadSummary, _)
summarize! = |reader| {
	var $lines_read = 0.U64
	var $longest_line_bytes = 0.U64
	for! item in reader.lines() {
		match item {
			Ok(line) => {
				$lines_read = $lines_read + 1
				$longest_line_bytes = $longest_line_bytes.max(line.count_utf8_bytes())
			}
			# A line that is not valid UTF-8 still counts as a line.
			Err(BadUtf8(_)) => {
				$lines_read = $lines_read + 1
			}
			Err(FileErr(err)) => {
				return Err(FileErr(err))
			}
		}
	}
	Ok({ lines_read: $lines_read, longest_line_bytes: $longest_line_bytes })
}
