app [main] { pf: platform "../../platform/main.roc" }

import pf.Ffi
import pf.Stdout
import pf.Task exposing [Task]

main =
    Ffi.withLib "examples/ffi/simple.module" \lib ->
        Stdout.line! "Loaded Successfully!!!"
        arg = Ffi.arg! "This came from Roc!\n"
        Stdout.line! "Created Arg!!!\n"
        Ffi.call! lib "say_hi" [arg]
        Stdout.line! "Completed!!!"

