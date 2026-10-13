## Write a file piece by piece: a report line by line, then a redacted copy
## made without holding more than one chunk of the file in memory.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.File
import pf.IOErr
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	report : Path
	report = "report.csv"
	redacted : Path
	redacted = "report-redacted.csv"

	rows = [
		{ name: "apples", total: 3.U64 },
		{ name: "pears", total: 12 },
		{ name: "plums", total: 240 },
	]
	write_report!(report, rows)?
	Stdout.write!("${report.display()}:\n${report.read_utf8!()?}")?

	copy_redacted!(report, redacted)?
	Stdout.write!("${redacted.display()}:\n${redacted.read_utf8!()?}")?

	# The mode decides what happens to a file that is already there.
	match File.open_writer!(report, RequireNew) {
		Err(PathErr(AlreadyExists, _)) => Stdout.line!("RequireNew left the existing report alone.")?
		Err(PathErr(err, path)) => {
			return Err(PathErr(err, path))
		}
		Ok(_) => {
			return Err(RequireNewReplacedTheReport)
		}
	}

	# Cleanup
	report.delete!()?
	redacted.delete!()?

	Ok({})
}

## Write the report a line at a time instead of building it in memory first.
## `File.with_writer!` flushes when the callback returns, and reports a failure
## of that flush.
write_report! : Path, List({ name : Str, total : U64 }) => Try({}, [PathErr(IOErr, Path), FileErr(IOErr)])
write_report! = |path, rows|
	File.with_writer!(
		path,
		Truncate,
		|writer| {
			writer.write_utf8!("name,total\n")?
			for row in rows {
				writer.write_utf8!("${row.name},${row.total.to_str()}\n")?
			}
			Ok({})
		},
	)

## Copy a file through a transformation, a chunk at a time. A failed read
## arrives as `SourceErr(FileErr(_))`, a failed write as `FileErr(_)`.
copy_redacted! : Path, Path => Try({}, _)
copy_redacted! = |source, destination| {
	reader = File.open_reader!(source)?
	File.with_writer!(
		destination,
		Truncate,
		|writer|
			writer.write_stream!(reader.chunks().map(|chunk| chunk.map_ok(redact))),
	)
}

## Replace every digit with `#`.
redact : List(U8) -> List(U8)
redact = |bytes|
	bytes.map(|byte| if byte >= '0' and byte <= '9' '#' else byte)

expect redact("pears,12\n".to_utf8()) == "pears,##\n".to_utf8()
expect redact([]) == []
