[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Froc-lang.org%2Fbadge%2Froc.json
[roc_link]: https://github.com/roc-lang/roc

# basic-cli

A Roc [platform](https://github.com/roc-lang/roc/wiki/Roc-concepts-explained#platform) for command-line programs.

`basic-cli` supports command execution, directories, environment variables, files, HTTP, locales, paths, random seeds, sleeping, SQLite, standard input/output/error, TCP, terminal raw mode, and UTC time.

## Supported targets

The platform builds and runs on these targets in CI:

| Roc target | Operating system | Architecture |
| --- | --- | --- |
| `x64mac` | macOS | x86-64 |
| `arm64mac` | macOS | ARM64 |
| `x64musl` | Linux (musl) | x86-64 |
| `arm64musl` | Linux (musl) | ARM64 |
| `x64win` | Windows | x86-64 |

Other targets are not currently supported. In particular, Windows support is
x86-64 only and uses the UCRT supplied with Windows 10 and 11. Applications do
not require a separate Visual C++ runtime installation. Windows library sources,
build commands, hashes and licenses accompany the platform bundle in
`targets/x64win/PROVENANCE.json` and `targets/x64win/licenses/`. The bundle's
`THIRD_PARTY_LICENSES.md` holds the notices for the third-party code linked
into every target's host.

## Host runtime behavior

These host behaviors may affect application design:

- HTTP and HTTPS use HTTP/1 only. [Issue #455](https://github.com/roc-lang/basic-cli/issues/455)
  tracks research into HTTP/2 support and its tradeoffs.
- HTTPS certificates are validated against bundled WebPKI roots, not the
  operating system trust store. A certificate trusted only through a locally
  installed OS root will therefore be rejected. [Issue #454](https://github.com/roc-lang/basic-cli/issues/454)
  tracks research into the appropriate trust configuration for basic-cli.
- The timeout configured on an HTTP `Request` is the deadline for the whole
  exchange, response body included; `NoTimeout` leaves it unbounded.
  `Http.send!` and the functions built on it buffer the response completely
  without a configurable size limit ([issue #436](https://github.com/roc-lang/basic-cli/issues/436)).
- `Http.send_streaming!` returns once the status and headers have arrived and
  hands the body over in chunks of at most 64 KiB, so a download need not fit
  in memory. Its `idle_timeout` (30 seconds unless set) bounds each single
  wait, for the headers and for each part of the body, so a large download can
  leave the `Request` at `NoTimeout`. After an idle timeout the response can
  still be read; the `Request` deadline passing is final. Each streaming
  response has its own connection, closed when the body ends or fails, or when
  the response and its streams are released. Request bodies are not streamed.
- HTTP redirects are opt-in through trailing options, `{ max_redirects: n }`;
  the default is zero. The request deadline covers every hop and the final
  body. Cross-origin hops strip credentials; HTTPS downgrades are refused.
- HTTP defaults to `User-Agent: roc-basic-cli/0.26`, preserving an explicit
  user agent. A non-empty body defaults to `Content-Type: text/plain` unless
  one is set; an empty body adds no content type.
- A spawned `Cmd.Child` is killed and reaped when its last reference is
  released; an unused `_child` binding does not keep it alive. `Pipe` output
  is read through `child.read!(duration)` and is absent from `child.wait!()`;
  choose `Capture` to retain it for `wait!`.
  `.stdout(File(path, Append, {}))` or `.stderr(File(path, Truncate, {}))`
  writes directly to disk with the writer modes and creation permissions.
  `MergeWithStdout` shares stdout's open file; file-backed streams do not
  consume capture or pending-output budgets.
- `Utc` supplies clock readings and signed epoch conversions. Use a package
  such as [roc-time](https://github.com/lukewilliamboswell/roc-time) for timestamp
  parsing, calendar calculations and richer formatting. Its documented profiles
  use microseconds, while `Utc` stores nanoseconds. `Utc.to_iso_8601` is a
  whole-second display; signed epoch nanoseconds preserve the stored instant.
- `Signal.catch!` catches Ctrl-C and, with a `System.Unix` witness, SIGTERM
  (including default `systemctl stop`). Blocking effects return bare
  `Interrupted`. Call `Signal.poll!()` before effectful application cleanup;
  catching a signal does not clean up external resources itself. Forced
  termination and systemd's eventual stop-timeout escalation remain uncatchable.
- `System.target!()` supplies opaque OS witnesses. `Cmd.exec!(unix, path, args)`
  replaces a Unix process at an exact path and bypasses Roc cleanup on success;
  `Cmd.call!(program, args)` runs a child and waits for success.
- UnixSocket pathname streams work on Linux, macOS, and Windows 10 version
  1803 (build 17134) or newer, including Windows 11. Path limits and native
  filesystem name restrictions apply. Closing does not unlink the socket.
- File writer options apply `OwnerOnly` or `PublicRead` permissions only when
  creating a new regular file. Existing files retain their access grants;
  use `RequireNew` with `OwnerOnly` for private files. Explicit permissions
  replace ACL grants and fail if the filesystem cannot enforce the policy.
- Several network and TLS failures currently use a generic HTTP transport
  error ([issue #438](https://github.com/roc-lang/basic-cli/issues/438)).
- TCP reads and writes always have a timeout: a `Tcp.Connection` holds the
  `io_timeout` it was created with, which bounds each read or write as a
  whole, and `with_timeout` returns the same connection with another. The wait
  to connect or accept is separate; only `accept!` may wait indefinitely
  (`NoTimeout`). `Duration.zero` expires immediately, and expiry is always
  `TcpErr(TimedOut)`.
- A TCP read that times out or is interrupted consumes nothing: the bytes that had arrived stay
  buffered for the next read. A write that times out may have sent any prefix.
- `Tcp.Connection.read_until!`, `read_line!` and `lines` stop at the
  connection's line limit (1 MiB unless changed with `with_line_limit`),
  preventing an untrusted peer from causing unbounded buffering. The rest of
  an over-long record is discarded before the next read returns.
- `File.Writer` buffers written bytes in the host; they reach the operating
  system when the buffer fills and on `flush!`. The file is closed when the
  last reference to the writer is released, which writes what is still
  buffered but cannot report a failure, so flush after the last write or use
  `File.with_writer!`. A crash loses buffered bytes.
- Every `Sqlite.open!` call opens its own connection; `Sqlite.open_in_memory!`
  and the path `":memory:"` open a new, private in-memory database each time.
  A connection waits up to five seconds for another connection's lock unless
  `busy_timeout` says otherwise. It is closed by `close!`, or when the `Db` and
  every unfinished `rows` stream made from it have been released. Each
  connection keeps up to 32 prepared statements, keyed by their SQL text, and
  drops the least recently used.

## Examples

The [examples](examples/) directory contains executable, application-shaped CLI
programs for common tasks like reading files, running commands, constructing
URLs, making HTTP requests, working with SQLite, and reading stdin.

The examples are pinned to the [`0.25.0` release](https://github.com/roc-lang/basic-cli/releases/tag/0.25.0):

```roc
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst" }
```

To run examples from a local checkout instead, build the platform first and use `"../platform/main.roc"`; see [CONTRIBUTING.md](CONTRIBUTING.md).

HTTP examples use Roc's builtin `Json` parser and encoder directly through
`Http.get!` and `Http.send_json!`.

## Documentation

- [`0.25.0` release documentation](https://roc-lang.github.io/basic-cli/0.25.0/)
- [latest main branch](https://roc-lang.github.io/basic-cli/main/)

## Nix

Fetch the pinned published platform without rebuilding its Rust hosts:

```sh
nix build github:roc-lang/basic-cli#platform  # result/main.roc and result/targets/
nix build github:roc-lang/basic-cli#bundle    # result is the original release archive
```

The default package is `platform`. These outputs provide the release recorded in
[`nix/release.json`](nix/release.json), rather than the current checkout's platform
sources. The flake also provides the compiler and dependency pins needed to build
applications offline; see the [downstream application example](nix/README.md).

## Help

Ask questions on [Roc Zulip](https://roc.zulipchat.com), especially in the `#beginners` stream.

## Contributing

Contributor setup, verification, generated glue, and documentation publishing notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
