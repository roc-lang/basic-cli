app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

# Demo of basic-cli Random functions

import pf.Stdout
import pf.Random
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    random_u64 = Random.random_u64!({})?
    Stdout.line!("Random U64 is: ${Inspect.to_str(random_u64)}")?

    random_u32 = Random.random_u32!({})?
    Stdout.line!("Random U32 is: ${Inspect.to_str(random_u32)}")?

    random_bytes = Random.random_bytes!(4)?
    Stdout.line!("Random bytes are: ${Inspect.to_str(random_bytes)}")
