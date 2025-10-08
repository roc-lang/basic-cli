module [
    IOErr,
    seed!,
]

import InternalIOErr
import Host


## Tag union of possible errors when getting a random seed.
##
## > This is the same as [`File.IOErr`](File#IOErr).
IOErr : InternalIOErr.IOErr

## Generate a random U64 using the system's source of randomness.
## This uses the Rust crate `getrandom`.
seed! : {} => Result U64 [RandomErr IOErr]
seed! = |{}|
    Host.random_seed!({})
    |> Result.map_err(|err| RandomErr(InternalIOErr.handle_err(err)))
