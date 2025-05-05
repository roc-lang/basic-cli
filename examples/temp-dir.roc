app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Path
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Prints the default temp dir
#
# !! this requires the flag `--linker=legacy`:
# for example: `roc build examples/temp-dir.roc --linker=legacy`

main! : List Arg => Result {} _
main! = |_args|

    temp_dir_path_str = Path.display(Env.temp_dir!({}))

    Stdout.line!("The temp dir path is ${temp_dir_path_str}")
