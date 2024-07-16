# basic-cli host

See [basic-cli-build-steps.png](../basic-cli-build-steps.png) to see how these crates
are used in the build process.

## roc_host

Every Roc platform needs a host.
The host contains code that calls the Roc main function and provides the Roc app with functions to allocate memory and execute effects such as writing to stdio or making HTTP requests.

## roc_host_bin

This crate wraps roc_host to build an executable. This executable is used by `roc preprocess-host ...`. That command generates an .rh and .rm file, these files are used by the [surgical linker](https://github.com/roc-lang/roc/tree/main/crates/linker#the-roc-surgical-linker). 

## roc_host_lib

This crate wraps roc_host and produces a static library (.a file). This .a file is used for legacy linking. Legacy linking refers to using a typical linker like ld or lld instead of the Roc [surgical linker](https://github.com/roc-lang/roc/tree/main/crates/linker#the-roc-surgical-linker).

## roc_std

Provides Rust representations of Roc data structures.