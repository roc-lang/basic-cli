app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Utc
import pf.Sleep

# Demo Utc and Sleep functions

main! = |_args| {
    start = Utc.now!({})

    # 1000 ms = 1 second
    Sleep.millis!(1000)

    finish = Utc.now!({})

    duration_ms = Utc.delta_as_millis(finish, start)
    duration_nanos = Utc.delta_as_nanos(finish, start)

    _r = Stdout.line!("Completed in ${duration_ms.to_str()} ms (${duration_nanos.to_str()} ns)")

    Ok({})
}
