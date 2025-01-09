app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Path

# To run this example: check the README.md in this folder

## Prints the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`
main! = \_args ->

    temp_dir_str = Path.display(Env.temp_dir!({}))

    Stdout.line!("The temp dir path is $(temp_dir_str)")
    |> Result.map_err(\err -> Exit(1, "Failed to print temp dir:\n\t$(Inspect.to_str(err))"))
