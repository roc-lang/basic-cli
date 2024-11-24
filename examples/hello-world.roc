app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env

main! = \{} ->
    platform = Env.platform! {}
    Stdout.line! (Inspect.toStr platform)
