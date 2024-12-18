app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep

main! = \{} ->
    start = Utc.now! {}

    Sleep.millis! 1500

    finish = Utc.now! {}

    duration = Num.toStr (Utc.delta_as_nanos start finish)

    Stdout.line! "Completed in $(duration)ns"
