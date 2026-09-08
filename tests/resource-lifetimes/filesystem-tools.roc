## Package a directory tree in a private workspace and clean it up after use.
app [main!] { pf: platform "../../platform/main.roc" }

import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| Env.with_temp_dir!(
	|workspace| {
		source = Path.join(workspace, "source")
		Path.create_dir!(source)?
		Path.write_utf8!(Path.join(source, "config.txt"), "ready")?
		bundle = Path.join(workspace, "bundle")
		Path.copy_dir!(source, bundle)?
		Path.copy!(Path.join(bundle, "config.txt"), Path.join(bundle, "backup.txt"))?
		resolved = Path.canonicalize!(bundle)?
		contents = Path.read_utf8!(Path.join(resolved, "backup.txt"))?
		expect contents == "ready"
		Stdout.line!("Copied files in a private workspace")
	},
)
