app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Path

## Prints the default temp dir
##
## !! requires --linker=legacy
## for example: `roc build examples/temp-dir.roc --linker=legacy`
main! = \_args ->

    tempDirStr = Path.display (Env.tempDir! {})

    Stdout.line! "The temp dir path is $(tempDirStr)"
    |> Result.mapErr \err -> Exit 1 "Failed to print temp dir:\n\t$(Inspect.toStr err)"
