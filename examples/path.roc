## Inspect a path's parent, filename, extension, and type (file/dir/symlink).
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |args| {
	path = path_argument(args)?
	parent = path.parent().map_ok(Path.display) ?? "<none>"
	filename = Path.filename(path).map_ok(Path.display) ?? "Path is not a file."
	extension = Path.ext(path).map_ok(Path.display) ?? "<none>"

	Stdout.line!(
		\\Path: ${Path.display(path)}
		\\Debug: ${Str.inspect(path)}
		\\Parent: ${parent}
		\\Filename: ${filename}
		\\Extension: ${extension}
		\\Type: ${Str.inspect(Path.type!(path)?)}
	)?

	Ok({})
}

path_argument = |args|
	match args {
		[first, ..] => Ok(Path.from_os_str(first))
		[] => Err(MissingPathArgument)
	}
