## Report the size in bytes of a path supplied on the command line.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |args| {

	file : Path
	file = path_argument(args)?

	file_size : U64
	file_size = file.size_in_bytes!()?

	Stdout.line!("${file.display()} is ${file_size.to_str()} bytes")?

	Ok({})
}

path_argument : List(OsStr) -> Try(Path, [MissingPathArgument, ..])
path_argument = |args|
	match args.drop_first(1) {
		[first, ..] => Ok(Path.from_os_str(first))
		[] => Err(MissingPathArgument)
	}
