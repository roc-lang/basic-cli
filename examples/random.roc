app [main!] { pf: platform "../platform/main.roc" }

# To run this example: check the README.md in this folder

# Demo of basic-cli Random functions

import pf.Stdout
import pf.Random
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    random_u64 = Random.random_seed_u64!({})?
    Stdout.line!("Random U64 seed is: ${Inspect.to_str(random_u64)}")?

    random_u32 = Random.random_seed_u32!({})?
    Stdout.line!("Random U32 seed is: ${Inspect.to_str(random_u32)}")

    # See the example linked below on how to generate a sequence of random numbers using a seed
    # https://github.com/roc-lang/examples/blob/main/examples/RandomNumbers/main.roc