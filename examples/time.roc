app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep

# Demo Utc and Sleep functions

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    start = Utc.now!({})

    # 1000 ms = 1 second
    Sleep.millis!(1000)

    finish = Utc.now!({})

    duration_nanos = finish - start
    duration_ms = duration_nanos // 1_000_000

    Stdout.line!("Completed in ${duration_ms.to_str()} ms (${duration_nanos.to_str()} ns)")

    Ok({})
}
