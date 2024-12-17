app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep

main! = \_args ->
    start = Utc.now! {}

    Sleep.millis! 1500

    finish = Utc.now! {}

    duration = Num.toStr (Utc.deltaAsNanos start finish)

    Stdout.line! "Completed in $(duration)ns"
