app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Tty

main! = |_args| {
    Stdout.line!("Tty: enabling raw mode")
    Tty.enable_raw_mode!()

    Stdout.line!("Tty: disabling raw mode")
    Tty.disable_raw_mode!()

    Ok({})
}
