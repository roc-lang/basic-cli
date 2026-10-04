## Create, inspect, and clean up a small directory tree.
app [main!] { pf: platform "../platform/main.roc" }

import pf.OsStr
import pf.Stdout
import pf.Path

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	# Best-effort cleanup from a previous interrupted run.
	workspace : Path
	workspace = "demo-workspace"

	workspace.delete_all!() ?? {}

	# Create a directory
	workspace.create_dir!()?

	# Create a directory and its parents
	components : Path
	components = "demo-workspace/src/components"

	components.create_all!()?

	# Create a child directory
	assets : Path
	assets = "demo-workspace/assets"

	assets.create_dir!()?

	# List the contents of a directory
	paths = workspace.list!()?

	displayed = paths.map(|path| path.display())

	# Check the contents of the directory
	expect paths.len() == 2
	expect displayed.contains("demo-workspace/src")
	expect displayed.contains("demo-workspace/assets")

	Stdout.line!("Workspace entries: ${Str.join_with(displayed, ", ")}")?

	# Delete all directories recursively
	workspace.delete_all!()?

	Stdout.line!("Workspace cleaned up.")?

	Ok({})
}
