## Read a file's accessed, modified, and creation timestamps.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0/4rAQg8kUYZ3Vksr4qMQHpaFYNiHSn9GgS7gVxghd1XYV.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Path
import pf.Utc

main! : List(OsStr) => Try({}, _)
main! = |args| {

	file : Path
	file = path_argument(args)?

	time_modified = Utc.to_millis_since_epoch(file.time_modified!()?)

	time_accessed = Utc.to_millis_since_epoch(file.time_accessed!()?)

	created_line = match file.time_created!() {
		Ok(time_created) => "    Created: ${Utc.to_millis_since_epoch(time_created).to_str()} ms since epoch"
		Err(PathErr(Unsupported)) => "    Created: unsupported"
		Err(err) => Err(err)?
	}

	Stdout.line!(
		\\${file.display()} file time metadata:
		\\    Modified: ${time_modified.to_str()} ms since epoch
		\\    Accessed: ${time_accessed.to_str()} ms since epoch
		\\${created_line}
		,
	)?

	Ok({})
}

## Parse the first argument into a Path
path_argument : List(OsStr) -> Try(Path, _)
path_argument = |args|
	match args.drop_first(1) {
		[first, ..] => Ok(Path.from_os_str(first))
		[] => Err(MissingPathArgument)
	}
