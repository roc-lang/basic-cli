## Generate random 32-bit and 64-bit seed values.
app [main!] { pf: platform "../platform/main.roc" }

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
