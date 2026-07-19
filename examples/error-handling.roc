## Handle errors with tag-pattern matching.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }

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

	# For professional software, use error tags (like `PathErr(NotFound)`) internally and convert
	# them to a message for the user at the edge of your program. This also makes it easy to provide
	# error messages in different languages.
	match missing_file.read_utf8!() {
		Ok(content) => Err(UnexpectedReadSuccess(content))?
		Err(PathErr(NotFound)) => Stderr.line!("Expected error: Path not found (NotFound)")?
		Err(PathErr(PermissionDenied)) => Stderr.line!("Error: Permission denied")?
		Err(PathErr(Other(msg))) => Stderr.line!("Error: ${msg}")?
		Err(_) => Stderr.line!("Error: Other file error")?
	}

	directory : Path
	directory = "examples"

	match directory.read_bytes!() {
		Err(PathErr(IsADirectory)) => Stderr.line!("Expected error: Path is a directory (IsADirectory)")?
		Ok(_) => Err(UnexpectedDirectoryReadSuccess)?
		Err(err) => Err(UnexpectedDirectoryReadError(err))?
	}

	regular_file : Path
	regular_file = "LICENSE"

	match regular_file.list!() {
		Err(PathErr(NotADirectory)) => Stderr.line!("Expected error: Path is not a directory (NotADirectory)")?
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
