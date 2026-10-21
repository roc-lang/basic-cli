## Read a file's accessed, modified, and creation timestamps.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst" }

import pf.Duration
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Utc

main! : List(OsStr) => Try({}, _)
main! = |args| {
	file : Path
	file = path_argument(args)?

	modified = file.time_modified!()?
	accessed = file.time_accessed!()?

	# Not every filesystem records when a file was created.
	created_line = match file.time_created!() {
		Ok(created) => "    Created: ${created.to_iso_8601()}"
		Err(PathErr(Unsupported, _path)) => "    Created: unsupported"
		Err(err) => Err(err)?
	}

	# The time between two instants is a Duration, which compares with others.
	age = Utc.now!().since(modified)
	freshness = if age > Duration.minutes(5) "stale" else "fresh"

	Stdout.line!(
		\\${file.display()} file time metadata:
		\\    Modified: ${modified.to_iso_8601()} (${freshness})
		\\    Accessed: ${accessed.to_iso_8601()}
		\\${created_line}
		,
	)?

	Ok({})
}

## Parse the first argument into a Path
path_argument : List(OsStr) -> Try(Path, _)
path_argument = |args|
	match args {
		[first, ..] => Ok(Path.from_os_str(first))
		[] => Err(MissingPathArgument)
	}
