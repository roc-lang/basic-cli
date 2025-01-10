app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep

# To run this example: check the README.md in this folder

main! = \_args ->
    start = Utc.now!({})

    Sleep.millis!(1500)

    finish = Utc.now!({})

    duration = Num.to_str(Utc.delta_as_nanos(start, finish))

    Stdout.line!("Completed in $(duration)ns")
