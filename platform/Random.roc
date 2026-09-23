import IOErr exposing [IOErr]
import Host

## Obtain random seed values from the operating system's entropy source.
Random :: [].{

	## Generate a random 64-bit unsigned integer seed.
	seed_u64! : () => Try(U64, [RandomErr(IOErr)])
	seed_u64! = || widen_random_err(Host.random_seed_u64!())

	## Generate a random 32-bit unsigned integer seed.
	seed_u32! : () => Try(U32, [RandomErr(IOErr)])
	seed_u32! = || widen_random_err(Host.random_seed_u32!())
}

## Rebuild the error union so it is open at call sites.
## Passing a hosted function's result straight through leaves the union closed,
## which stops `?` from combining it with other error types.
widen_random_err : Try(v, [RandomErr(IOErr)]) -> Try(v, [RandomErr(IOErr)])
widen_random_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(RandomErr(err)) => Err(RandomErr(err))
	}
