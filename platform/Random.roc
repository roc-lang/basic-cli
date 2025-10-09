module [
    IOErr,
    random_u64!,
    random_u32!,
    random_bytes!,
]

import InternalIOErr
import Host


## Tag union of possible errors when getting a random seed.
##
## > This is the same as [`File.IOErr`](File#IOErr).
IOErr : InternalIOErr.IOErr

## Generate a random U64 using the system's source of randomness.
##
## This uses Rust's [getrandom](https://crates.io/crates/getrandom) crate to produce
## a single random 64-bit integer. Note that this is a direct interface to the
## system's source of randomness, meaning that each call introduces a significant
## amount of overhead. If you need to generate a lot of random numbers, consider
## calling this function once to generate a single "seed", then using a library
## such as [roc-random](https://github.com/lukewilliamboswell/roc-random) to generate
## additional random numbers.
##
## > Note that 64 bits is NOT considered sufficient randomness for cryptographic
## applications such as encryption keys. Prefer using `random_bytes()` to generate
## larger random values for security-sensitive applications.
random_u64! : {} => Result U64 [RandomErr IOErr]
random_u64! = |{}|
    Host.random_u64!({})
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))

## Generate a random U32 using the system's source of randomness.
##
## This uses Rust's [getrandom](https://crates.io/crates/getrandom) crate to produce
## a single random 32-bit integer. Note that this is a direct interface to the
## system's source of randomness, meaning that each call introduces a significant
## amount of overhead. If you need to generate a lot of random numbers, consider
## calling this function once to generate a single "seed", then using a library
## such as [roc-random](https://github.com/lukewilliamboswell/roc-random) to generate
## additional random numbers.
##
## > Note that 32 bits is NOT considered sufficient randomness for cryptographic
## applications such as encryption keys. Prefer using `random_bytes()` to generate
## larger random values for security-sensitive applications.
random_u32! : {} => Result U32 [RandomErr IOErr]
random_u32! = |{}|
    Host.random_u32!({})
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))

## Generate an arbitrary number of bytes using the system's source of randomness.
## For additional details on the specific source of randomness used on various
## platforms, see the Rust crate [getrandom](https://docs.rs/getrandom/0.3.3/getrandom/index.html).
random_bytes! : U64 => Result (List U8) [RandomErr IOErr]
random_bytes! = |count|
    Host.random_bytes!(count)
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))
