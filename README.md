[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
[roc_link]: https://github.com/roc-lang/roc

# basic-cli

A Roc [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) to work with files, commands, HTTP, TCP, command line arguments,...

:eyes: **examples**:
  - [latest main branch](https://github.com/roc-lang/basic-cli/tree/main/examples)

:book: **documentation**:
  - TBA -- `roc docs` not yet implemented in the new compiler

## Running Locally

**⚠️ IMPORTANT**: This branch (`migrate-zig-compiler`) requires the new Roc compiler and `roc_std_new` to be at matching versions to avoid ABI layout mismatches.

### Roc Nightly Version

This project uses pre-built Roc nightly releases from [roc-lang/nightlies](https://github.com/roc-lang/nightlies). The pinned nightly version is specified in `Cargo.toml` via the `# roc-nightly:` comment and `roc_std_new` rev.

The CI scripts automatically download the correct nightly based on this configuration. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to update the Roc version.

### Migration Status

This branch migrates basic-cli to the new Zig-based Roc compiler and RocOps ABI.

**✅ Completed:**
- All core modules (Cmd, File, Dir, Path, Env, Random, Sleep, Utc, Stdin/Stdout/Stderr)
- Single-variant tag union layout fix (RocSingleTagWrapper now correctly includes discriminant)
- Comprehensive testing and verification

**Note:** Single-variant tag unions (e.g., `[PathErr(IOErr)]`) are represented in the Roc ABI with a discriminant byte (always 0) even though there's only one variant. The `RocSingleTagWrapper<T>` type implements this standard Roc ABI layout. This type could potentially be upstreamed to `roc_std_new` for reuse across platforms.
