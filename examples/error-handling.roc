## Handle errors with tag-pattern matching.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Stderr
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {

	file_name : Path
	file_name = "test-file.txt"

	# Try to read a file that doesn't exist - should error
	missing_file : Path
	missing_file = "nonexistent-file.txt"

	# For professional software, use error tags (like `PathErr(NotFound, path)`) internally and convert
	# them to a message for the user at the edge of your program. This also makes it easy to provide
	# error messages in different languages.
	match missing_file.read_utf8!() {
		Ok(content) => Err(UnexpectedReadSuccess(content))?
		# The failing path comes back with the error, so we can show it to the user.
		Err(PathErr(NotFound, path)) => Stderr.line!("(Expected ✅) error: Path not found (NotFound): ${path.display()}")?
		Err(PathErr(PermissionDenied, path)) => Stderr.line!("Unexpected Error: Permission denied for path:\n\t${path.display()}")?
		Err(PathErr(Other(msg), path)) => Stderr.line!("Unexpected Error:\n\t${msg}\nFor path:\n\t${path.display()}")?
		Err(err) => Stderr.line!("Unexpected Error: ${Str.inspect(err)}")?
	}

	directory : Path
	directory = "examples"

	match directory.read_bytes!() {
		Err(PathErr(IsADirectory, path)) => Stderr.line!("(Expected ✅) error: Path is a directory: ${path.display()}")?
		Ok(_) => Err(UnexpectedDirectoryReadSuccess)?
		Err(err) => Err(UnexpectedDirectoryReadError(err))?
	}

	regular_file : Path
	regular_file = "LICENSE"

	match regular_file.list!() {
		Err(PathErr(NotADirectory, path)) => Stderr.line!("(Expected ✅) error: Path is not a directory: ${path.display()}")?
		Ok(_) => Err(UnexpectedFileListSuccess)?
		Err(err) => Err(UnexpectedFileListError(err))?
	}

	file_name.write_utf8!("Hello from error-handling example!") ? |err| FileWriteFailed(err)

	content = file_name.read_utf8!() ? |err| FileReadFailed(err)

	# Cleanup
	file_name.delete!() ? |err| FileDeleteFailed(err)

	Stdout.line!("${file_name.display()} contains: ${content}")?

	Ok({})
}
