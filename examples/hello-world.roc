app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Task exposing [Task]

main =
    dir = Env.tmpDir!
    Stdout.line! "$(dir)"
