app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

import pf.Stdin
import pf.Stdout
import pf.Stderr

main! = |_args|
    data = Stdin.bytes!({})?
    Stderr.write_bytes!(data)?
    Stdout.write_bytes!(data)?
    Ok {}
