# Contributing

Thanks for helping improve `basic-cli`.

CI uses a pinned Roc nightly from [`roc-lang/nightlies`](https://github.com/roc-lang/nightlies).
For local work, use the `nightly-tag` pinned in [the CI workflow](.github/workflows/ci.yml),
matching the generated ABI. Download the archive for that tag and your operating
system from [`roc-lang/nightlies` releases](https://github.com/roc-lang/nightlies/releases).

## Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all. See the [Code of Conduct](https://github.com/roc-lang/roc/blob/main/CODE_OF_CONDUCT.md) for details.

## Version Requirements

Check the compiler available locally:

```sh
roc version
```

To install the pinned nightly locally, extract the downloaded archive and add
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
4. Run the Rust checks under [Verification](#verification) and `./scripts/test.py`.

## Verification

### Windows host inputs

Build the host on Windows x64 with Python 3.11 or newer, the pinned Rust toolchain,
Zig 0.17.0 on `PATH` (or selected with `ZIG`), and the Windows SDK/MSVC build tools used by Rust's MSVC
target. Install Rust's notices and LLVM tools with
`rustup component add rust-docs llvm-tools-preview`. The Rust target remains
`x86_64-pc-windows-msvc`; `zig cc` builds ring and SQLite using that ABI and
the SDK headers. A small adapter translates the target flags from Cargo's C
build tooling; a separate LLVM/clang-cl installation is unnecessary. All Windows
build steps use the same version-checked executable. The adapter is copied to a
path derived from the compiler's path and SHA-256 and both adapter files' hashes,
so changing these inputs invalidates Cargo's cached native builds.

Run `python scripts/build.py --target x64win`, followed by
`python -m unittest scripts/test_windows_runtime.py`. The build generates the
startup archive and UCRT/Win32 import libraries, combines them into
`windows_support.lib`, then collects the actual Cargo
and Rust notices. `python scripts/windows_runtime.py --check` verifies the
library and notice inventories before bundling. Release artifacts must transfer
the entire `platform/targets/x64win/` directory, including `PROVENANCE.json` and
`licenses/`. Empty target placeholders are permitted only by the explicit local
test-bundle option.

The runtime uses the UCRT supplied with Windows 10 and 11. Vendored Roc sources
are checked against `native/windows/UPSTREAM.json`; update the recorded source
revision, hashes and original license together when changing them. New native
dependencies or license expressions need review before adding them to the
producer's accepted set.

For changes to the Nix release outputs, run `nix flake check`. This builds and
runs an application against the pinned published platform inside the Nix sandbox;
see [the Nix consumer documentation](nix/README.md).

CI formats, lints, and unit-tests the Rust host on Linux, macOS, and Windows.
Run the same commands before pushing host changes:

```sh
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
```

Clippy runs with warnings denied. `src/roc_platform_abi.rs` is generated, so
any Clippy lint it needs relaxed is allowed on its `mod` declaration in
`src/lib.rs` with a comment saying why, not by hand-editing the generated file
or crate-wide.

Release-tooling regression tests run with:

```sh
python3 -m unittest scripts/test_check_release_version.py scripts/test_check_release_branch.py scripts/test_check_version_bump.py scripts/test_update_nix_release.py scripts/test_check_roc_nightly.py scripts/test_windows_runtime.py
```

Stable releases must be dispatched from the default branch. To publish a branch
candidate, dispatch the Release workflow on that branch with an `X.Y.Z-rcN`
version. Branch candidates run the same build and bundle tests, publish a GitHub
prerelease with its docs archive, and skip default-branch follow-up PRs and Pages
publication. Commit the matching Cargo version on the candidate branch before
dispatching so the release tag records the versioned sources.

The release workflow bounds `roc bump` to 120 seconds and saves its output in
`.release/bump-output.txt`. It currently warns on comparison errors and timeouts:
`roc bump` cannot extract a public API that mentions a type the platform header
does not expose, and in the 0.25.0 predecessor the `Sqlite` row decoders take
the unexposed `Host.SqliteStmt`. Switch to `--mode require` once the
predecessor is a release without such a type.

Run the full local check before opening release or CI-facing changes:

```sh
./scripts/test.py
```

Set `ROC` to test with a specific compiler without changing `PATH`:

```sh
ROC=/path/to/roc ./scripts/test.py
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

Native resource handles (file readers, sockets, listeners, child processes,
SQLite statements) are checked on every OS by the suite itself. A run case with
`"live_handles": 0` in `scripts/test_spec.json` sets `BASIC_CLI_LIVE_HANDLES`,
which makes the host print how many handles are still open after `main!`
returns, and requires the total to be zero:

```text
live handles: 0
live handles[Child]: 0
live handles[FileReader]: 0
...
```

The report goes to stderr, covers normal returns, errors and exit codes, and is
not printed when the program crashes. Every example that opens a handle carries
the assertion, as do the fixtures in `tests/resource-lifetimes/`, which verify
port release, stream EOF, shared aliases, command reuse, and early returns. Add
it to the cases of any new app that opens a handle. Rust tests in
`src/resources.rs` verify exactly-once native finalization, and others verify
child reaping.

The counters are the only check that sees a leaked handle. Handle boxes live in
the host's own address ranges rather than on the heap (see `src/resources.rs`),
so they are invisible to Valgrind, and the native value behind a leaked handle
stays reachable from its slot instead of being reported as lost.

Valgrind still checks everything else, but the static musl allocator is
invisible to its heap accounting: a report of zero heap allocations alone does
not prove cleanup. On x86_64 glibc Linux, run the additional ownership check
used by CI:

```sh
ROC=/path/to/pinned/roc python3 scripts/test_resource_lifetimes.py
```

It creates an isolated diagnostic platform under `target/`, uses glibc so
Valgrind observes allocations, and runs the `tests/resource-lifetimes/` fixtures
against a debug host. It rejects memory errors, definite/indirect leaks and a
non-zero live-handle total, and tracks file descriptors. Runtime reactor
descriptors and reachable service state can remain until process exit.

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

## API conventions

New public API is reviewed against these rules. A proposal states its
decisions and assumptions, not open questions.

### Methods

- An operation on a value is a method on that value's type, called with
  receiver syntax: `reader.lines()`. Module-level functions are for
  constructors and entry points (`Tcp.connect!`, `Duration.seconds(5)`) and
  process-global things (`Stdin.line!()`).
- Prefer the dispatched names: `to_str`, `to_inspect`, `is_eq`, operators, `map`.

### Options

- One function per operation. Tuning goes in a trailing nominal options record
  with defaulted fields (`{}` for all defaults); no `_with` twins, no options
  argument where nothing needs tuning.
- Positional arguments are the subject, the data and the amount requested. One
  mandatory value is positional.
- A setting that outlives one call (a timeout, a line limit) is held by the
  handle and changed with a pure `with_…` method.

### Timeouts and limits

- A timeout is a `Duration`; zero expires immediately. Mandatory: positional.
  Optional: `timeout : [NoTimeout, After(Duration)] ?? NoTimeout`, or a finite
  default where waiting forever is a bad one.
- Builders take `timeout(Duration)`; uncalled means no deadline.
- The wait to connect or accept is separate from the resulting connection's
  I/O timeout.
- Expiry is never a bare `TimedOut` beside a wrapper. Where the cause is
  `IOErr` it is that variant, `TcpErr(TimedOut)`. Inside a module's nominal
  error it is `IOErr(TimedOut)`; a whole-operation deadline may be its own
  variant (`Cmd.Err.TimedOut(PartialOutput)`). Http follows
  [#438](https://github.com/roc-lang/basic-cli/issues/438).
- A byte limit is `max_bytes : U64`, or `[NoLimit, MaxBytes(U64)]` where
  unlimited is legal; exceeding one is `ReadLimitExceeded(U64)`. Only network
  reads have a default line limit.

### End of input and streams

- A single read ends with `Err(EndOfInput)`; a short fixed-size read is
  `Err(UnexpectedEndOfInput)`; an empty `Ok` is real data. Lines exclude the
  terminator and one trailing `\r`.
- `BadUtf8` is always the builtin's
  `BadUtf8({ problem : Str.Utf8Problem, index : U64 })`, produced by
  `Str.from_utf8(bytes)?`, never re-wrapped.
- `chunks`, `lines` and `rows` are pure, infallible and do no I/O. `chunks`
  takes no argument on any source; the host picks the size, at most 64 KiB.
- Items are `Try(value, err)`. A source error, including a timeout, is the last
  item; the handle stays usable and a new stream may be started. An error about
  one item (`BadUtf8`, `ReadLimitExceeded` on one network line, a row whose
  values do not decode) is not terminal. One that would recur on every item (a
  missing column) is a source error, reported once.
- Examples name every per-item tag; none writes `Err(_) => {}` on a stream item.
- No read-ahead in Roc: a stream over a source other calls also read (`Stdin`,
  `File.Reader`, `Tcp.Connection`) buffers nothing a later direct read would
  miss; batch in the host.

### Naming

- `!` if and only if effectful. `_utf8` / `_bytes` only distinguish two
  existing forms of one operation.
- Builtin names keep their builtin meaning; unit constructors
  (`Duration.seconds(5)`) omit `from_`.
- No `..` in a result type: the compiler warns.

### Errors

- The `err` of every public `Try` is a structural tag union; nominal types are
  payloads only. Only typed values cross the host boundary.
- A module's failures arrive under `<Module>Err(cause)`; the cause is `IOErr`
  or the module's nominal error, in which an OS failure is `IOErr(IOErr)`. A
  second wrapper needs a different payload and a stated reason:
  `PathErr(IOErr, Path)` carries the path, `SourceErr(err)` a caller's stream
  error.
- Every nominal error type declares `is_eq : _` and `to_str`, and may declare
  `to_inspect`.
- Conditions callers match on sit bare beside the wrapper: `EndOfInput`,
  `UnexpectedEndOfInput`, `BadUtf8`, `ReadLimitExceeded`, `Closed`, `NoRows`,
  `BadExitStatus`.

### Handles

- Handles are cleaned up on last release; `close!` exists only where closing
  can fail or its timing matters.
- `Closed` is one bare tag, only on types with `close!`: no `DbClosed`. A
  scoped function that closes for the caller (`File.with_writer!`) does not
  return it.

### At a call site

A module that follows the rules reads like this:

```roc
conn = Demo.connect!("example.org", { connect_timeout: Duration.seconds(1), io_timeout: Duration.seconds(5) })?
expect conn.with_timeout(Duration.zero).read_line!() == Err(DemoErr(TimedOut))

for! item in conn.lines() {
    match item {
        Ok(line) => Stdout.line!(line)?
        Err(BadUtf8(_)) => {}
        Err(ReadLimitExceeded(_)) => {}
        Err(DemoErr(err)) => { return Err(DemoErr(err)) }
    }
}
```

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
