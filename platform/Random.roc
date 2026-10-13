import IOErr
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

## Rebuild the error union so app authors get an open row.
##
## An error row that crosses the host boundary is closed by design, and a
## wrapper that forwards the hosted result keeps that closed row. Every public
## function here rebuilds the union instead, so its error combines with others
## in every call form, including `seed! = Random.seed_u64!` followed by `seed!()?`.
## `tests/error-rows.roc` covers that form.
widen_random_err : Try(v, [RandomErr(IOErr)]) -> Try(v, [RandomErr(IOErr)])
widen_random_err = |result|
	match result {
		Ok(value) => Ok(value)
		Err(RandomErr(err)) => Err(RandomErr(err))
	}
