app [main!] { pf: platform "../platform/main.roc" }

# Demo of basic-cli Random functions

import pf.Stdout
import pf.Random

main! = |_args| {
    result = Random.seed_u64!({})
    match result {
        Ok(random_u64) => {
            Stdout.line!("Random U64 seed is: ${random_u64.to_str()}")
            Ok({})
        }
        Err(_) => {
            Stdout.line!("Failed to generate random seed")
            Err(Exit(1))
        }
    }
}
