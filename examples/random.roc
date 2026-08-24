## Generate random 32-bit and 64-bit seed values.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.0/F1JVZPYfWP71s8vk6tHcV1Qx1Ef6CZkwswGoCn8VHZmL.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Random

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	random_u64 = Random.seed_u64!()?
	Stdout.line!("Random U64 seed is: ${random_u64.to_str()}")?

	random_u32 = Random.seed_u32!()?
	Stdout.line!("Random U32 seed is: ${random_u32.to_str()}")?

	# TODO link to example showing how to use the seed values to generate random numbers

	Ok({})
}
