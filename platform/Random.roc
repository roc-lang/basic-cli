Random := [].{
    IOErr := [NotFound, PermissionDenied, BrokenPipe, AlreadyExists, Interrupted, Unsupported, OutOfMemory, Other(Str)]

    ## Generate a random 64-bit unsigned integer seed.
    seed_u64! : {} => Try(U64, [RandomErr(IOErr)])

    ## Generate a random 32-bit unsigned integer seed.
    seed_u32! : {} => Try(U32, [RandomErr(IOErr)])
}
