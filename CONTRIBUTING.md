# Contributing

Thanks for helping improve `basic-cli`.

CI uses a pinned Roc nightly from [`roc-lang/nightlies`](https://github.com/roc-lang/nightlies).
For local work, use any recent `roc` on `PATH`, or download the latest archive
for your operating system from the
[`roc-lang/nightlies` releases](https://github.com/roc-lang/nightlies/releases/latest).

## Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all. See the [Code of Conduct](https://github.com/roc-lang/roc/blob/main/CODE_OF_CONDUCT.md) for details.

## Version Requirements

Check the compiler available locally:

```sh
roc version
```

To install the latest nightly locally, extract the downloaded archive and add
the directory containing the `roc` executable to your `PATH`.

## Nix Development Environment

With Nix's `nix-command` and `flakes` features enabled, the flake provides the
pinned Roc nightly, the Rust toolchain and cross-compilation standard
libraries, Zig, Python, Valgrind (Linux only), and the documentation preview
server on supported Linux and macOS systems. Enter it with:

```sh
nix develop
```

To load the shell automatically, install [`direnv`](https://direnv.net/) and
hook it into your shell. The checked-in `.envrc` uses direnv's `use flake`;
install [`nix-direnv`](https://github.com/nix-community/nix-direnv) as well if
your direnv version does not provide it. Then simply approve `.envrc` once:

```sh
direnv allow
```

The lock file pins every flake input. The Roc nightly is pinned on top of that,
by release tag in `flake.nix`, and must name the same nightly the workflows
pin so the shell and CI cannot drift apart; see
[Updating Roc Glue](#updating-roc-glue). The tags come from
[`roc-overlay`](https://github.com/roc-lang/roc-overlay), which mirrors the
official [`roc-lang/nightlies`](https://github.com/roc-lang/nightlies)
binaries. After editing the tag, refresh that input so the new nightly is
recorded:

```sh
nix flake update roc-overlay
```

Bumping `channel` in `rust-toolchain.toml` similarly needs

```sh
nix flake update rust-overlay
```

whenever the requested version is newer than the manifests in the locked
[`rust-overlay`](https://github.com/oxalica/rust-overlay).

## Updating Roc Glue

CI pins a specific nightly so the compiler and committed host ABI glue cannot
drift independently. When updating the nightly pin in the workflows:

1. Update `flake.nix` to the same `rocpkgs` release tag, then run
   `nix flake update roc-overlay`.
2. Run `./ci/regenerate_glue.sh` to refresh `src/roc_platform_abi.rs`.
3. Reconcile `src/lib.rs` if generated names or layouts changed.
4. Run `cargo check` and `./scripts/test.py`.

## Verification

Run the full local check before opening release or CI-facing changes:

```sh
./scripts/test.py
```

The default command builds and bundles the native host, serves the bundle from
localhost, then formats, checks, tests, builds, and runs every example. Process
input, environment, fixtures, helper servers, exit codes, and separate stdout
and stderr assertions work on Unix and Windows.

The data in `scripts/test_spec.json` is the source of truth for the test matrix.
Every example must have exactly one entry. Set its `enabled` flag to `false`
to skip the app, or set a stage flag to `false` under `stages` or
`platforms.windows` to skip only a broken stage without changing the runner.
Add named objects to an app's `cases` array to run the same compiled binary
with different arguments, stdin, environment, fixtures, helper servers,
expected exit codes, or output assertions. `happy` is only a naming convention;
an app can have any number of successful and failing cases.

CI separates source validation, cross-target compilation, and native execution.
Every example is compiled for each target declared in `platform/main.roc`:
`x64mac`, `arm64mac`, `x64win`, `x64musl`, and `arm64musl`. Target-specific
binary artifacts are then downloaded and executed on matching native runners;
this includes `arm64musl`, which runs on an arm64 Linux runner.

The operations can also be run independently:

```sh
./scripts/test.py --operation validate
./scripts/test.py --operation build --target x64musl --artifact-dir dist/example-binaries
./scripts/test.py --operation run --target x64musl --artifact-dir dist/example-binaries
```

On Linux, run those native artifacts under Valgrind with the same cases and
output assertions used by CI:

```sh
./scripts/test.py --operation run --target x64musl --artifact-dir dist/example-binaries --valgrind
```

For faster local iterations when the platform host is already built:

```sh
./scripts/test.py --no-build
```

Build and validation operations bundle the current platform and temporarily
rewrite example headers to use its localhost URL. Checked-in examples may
therefore keep using the latest published release URL while local work and pull
requests exercise the WIP platform.

## Rust Glue

The Rust host ABI is generated from `platform/main.roc` using Roc's `RustGlue.roc` generator:

```sh
./ci/regenerate_glue.sh
./ci/regenerate_glue.sh --check
```

Commit `src/roc_platform_abi.rs` with any platform API change and the matching Rust host updates.

The script defaults to a sibling `../roc` checkout. Override paths when needed:

```sh
ROC=../roc/zig-out/bin/roc ROC_SRC=../roc ./ci/regenerate_glue.sh
```

Use `ci/regenerate_glue.sh --check` separately when reviewing platform ABI changes; CI intentionally treats the committed Rust glue as the host ABI source of truth.

Do not edit generated glue by hand.

## Examples

Every checked-in example should pass `roc check`, `roc test`, and `roc build`
with the current nightly.

Examples are executable documentation for representative, realistic workflows;
they are not intended to exhaustively exercise every public API function.

Examples should include a top-level `main!` annotation. When the full platform error row would distract from the example, map low-level errors into a small example-domain error or use `_` for the error type. Prefer postfix `?`, infix `?`, or `??` for effect results instead of ignoring them.

HTTP examples use Roc's builtin `Json` parser directly through `Http.get!`.

Examples that are intentionally kept out of CI while an API or compiler blocker is tracked use the `.todoroc` extension and must include a TODO comment with a GitHub issue link. Rename them back to `.roc` only after they check and build with the current nightly.

## Documentation

Generate platform docs from the platform entrypoint:

```sh
ROC_DOCS_URL_ROOT=/basic-cli/main roc docs --output=generated-docs platform/main.roc
```

The documentation entrypoint is `platform/main.roc`, matching the package that
applications consume.

To preview generated docs locally:

```sh
cd generated-docs
simple-http-server --nocache --index
```

The release workflow attaches `docs.tar.gz`, updates checked-in examples to the
new bundle URL, and opens a follow-up PR for those source changes. It also
reconstructs the versioned documentation site from release assets and deploys
the validated docs immediately. The Pages workflow performs the same
reconstruction and adds freshly generated `main` docs without committing
generated documentation to the repository.
