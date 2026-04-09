app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout
import pf.Stderr

# To run this example: check the README.md in this folder

main! = |_args| {
    data = Stdin.bytes!({})?
    Stderr.write_bytes!(data)?
    Stdout.write_bytes!(data)?
    Ok({})
}