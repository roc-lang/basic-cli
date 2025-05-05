app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.File
import pf.Utc
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

main! : List Arg => Result {} _
main! = |_args|
    file = "LICENSE"

    # NOTE: these functions will not work if basic-cli was built with musl, which is the case for the normal tar.br URL release.
    # See https://github.com/roc-lang/basic-cli?tab=readme-ov-file#running-locally to build basic-cli without musl.

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