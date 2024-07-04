app [main] { pf: platform "../../platform/main.roc" }

import pf.Ffi
import pf.Stdout
import pf.Task exposing [Task]

main =
    Ffi.withLib "examples/ffi/simple.module" \lib ->
        Stdout.line! "Loaded Successfully!!!"
        Stdout.line! "Sending Call to over FFI...\n"
        res = Ffi.call! lib "say_hi" "This came from Roc!\n"
        Stdout.line! "FFI sent this message back:\n"
        Stdout.line! res

