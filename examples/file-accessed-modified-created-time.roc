app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdout
import pf.File
import pf.Utc

main! = |_args|
    file = "LICENSE"

    time_modified = Utc.to_iso_8601(File.time_modified!(file)?)

    time_accessed = Utc.to_iso_8601(File.time_accessed!(file)?)

    time_created = Utc.to_iso_8601(File.time_created!(file)?)


    Stdout.line!(
        """
        ${file} file time metadata:
            Modified: ${Inspect.to_str(time_modified)}
            Accessed: ${Inspect.to_str(time_accessed)}
            Created: ${Inspect.to_str(time_created)}
        """
    )