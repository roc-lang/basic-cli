app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

# Demo of basic-cli Random functions

import pf.Stdout
import pf.Random
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    seed = Random.seed!({})?

    Stdout.line!("Seed is: ${Inspect.to_str(seed)}")
