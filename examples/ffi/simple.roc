app [main] { pf: platform "../../platform/main.roc" }

import pf.Ffi
import pf.Stdout
import pf.Task exposing [Task]

main =
    Ffi.withLib "examples/ffi/simple.module" \lib ->
        Stdout.line! "Loaded Successfully!!!"
        Ffi.call! lib "say_hi"
        Stdout.line! "Completed!!!"

