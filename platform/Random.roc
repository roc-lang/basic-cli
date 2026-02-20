import IOErr exposing [IOErr]

Random := [].{
    ## Generate a random 64-bit unsigned integer seed.
    seed_u64! : {} => Try(U64, [RandomErr(IOErr)])

    ## Generate a random 32-bit unsigned integer seed.
    seed_u32! : {} => Try(U32, [RandomErr(IOErr)])
}
