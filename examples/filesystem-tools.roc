## Prepare a distributable directory without changing its source files.
## Usage: roc filesystem-tools.roc -- path/to/site path/to/new-release
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.23.0-rc1/3hT3SoHZ6qbEsa9qVFLUW3547U5LeoNd1KbpqLpz4r1i.tar.zst" }

import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	(source_arg, destination_arg) = match args {
		[source, destination] => (source, destination)
		_ => return Err(MissingPaths)
	}
	source = Path.from_os_str(source_arg)
	destination = Path.from_os_str(destination_arg)

	# Prepare everything in a private workspace. It is removed on success or error.
	Env.with_temp_dir!(
		|workspace| {
			staged = Path.join(workspace, "release")
			Path.copy_dir!(source, staged)?
			Path.write_utf8!(Path.join(staged, "RELEASE.txt"), "Prepared with basic-cli\n")?

			# The destination must be new, protecting an existing release from overwrite.
			Path.copy_dir!(staged, destination)?
			Ok({})
		},
	)?
	resolved = Path.canonicalize!(destination)?
	Stdout.line!("Release prepared at ${Path.display(resolved)}")
}
