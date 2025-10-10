module [
    IOErr,
    random_seed_u64!,
    random_seed_u32!,
]

import InternalIOErr
import Host


## Tag union of possible errors when getting a random seed.
##
## > This is the same as [`File.IOErr`](File#IOErr).
IOErr : InternalIOErr.IOErr

## Generate a random `U64` seed using the system's source of randomness.
## A "seed" is a starting value used to deterministically generate a random sequence. 
##
## > !! This function is NOT cryptographically secure.
##
## This uses the [`u64()`](https://docs.rs/getrandom/latest/getrandom/fn.u64.html) function
## of the [getrandom crate](https://crates.io/crates/getrandom) to produce
## a single random 64-bit integer.
##
## For hobby purposes, you can just call this function repreatedly to get random numbers.
## In general, we recommend using this seed in combination with a library like
## [roc-random](https://github.com/lukewilliamboswell/roc-random) to generate additional
## random numbers quickly.
##
random_seed_u64! : {} => Result U64 [RandomErr IOErr]
random_seed_u64! = |{}|
    Host.random_u64!({})
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))

## Generate a random `U32` seed using the system's source of randomness.
## A "seed" is a starting value used to deterministically generate a random sequence. 
##
## > !! This function is NOT cryptographically secure.
##
## This uses the [`u32()`](https://docs.rs/getrandom/0.3.3/getrandom/fn.u32.html) function
## of the [getrandom crate](https://crates.io/crates/getrandom) to produce
## a single random 32-bit integer.
##
## For hobby purposes, you can just call this function repreatedly to get random numbers.
## In general, we recommend using this seed in combination with a library like
## [roc-random](https://github.com/lukewilliamboswell/roc-random) to generate additional
## random numbers quickly.
##
random_seed_u32! : {} => Result U32 [RandomErr IOErr]
random_seed_u32! = |{}|
    Host.random_u32!({})
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))