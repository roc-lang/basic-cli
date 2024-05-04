app [main] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Task exposing [Task]

main =
    Stdout.line! "Hello, World!"
