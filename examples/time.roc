app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep
import pf.Arg exposing [Arg]

# To run this example: check the README.md in this folder

# Demo Utc and sleep functions

main! : List Arg => Result {} _
main! = |_args|
    start = Utc.now!({})

    # 1000 ms = 1 second
    Sleep.millis!(1000)

    finish = Utc.now!({})

    duration = Num.to_str(Utc.delta_as_nanos(start, finish))

    Stdout.line!("Completed in ${duration} ns")
