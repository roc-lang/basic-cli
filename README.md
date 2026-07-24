[![Roc-Lang][roc_badge]][roc_link]

[roc_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fpastebin.com%2Fraw%2FcFzuCCd7
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
x86-64 only.

## Host runtime behavior

These current host-level limitations may affect application design:

- HTTP and HTTPS use HTTP/1 only. [Issue #455](https://github.com/roc-lang/basic-cli/issues/455)
  tracks research into HTTP/2 support and its tradeoffs.
- HTTPS certificates are validated against bundled WebPKI roots, not the
  operating system trust store. A certificate trusted only through a locally
  installed OS root will therefore be rejected. [Issue #454](https://github.com/roc-lang/basic-cli/issues/454)
  tracks research into the appropriate trust configuration for basic-cli.
- The timeout configured on an HTTP `Request` covers the request and response;
  `NoTimeout` leaves it unbounded. Responses are buffered completely without a
  configurable size limit ([issue #436](https://github.com/roc-lang/basic-cli/issues/436)),
  and several network and TLS failures currently use a generic transport error
  ([issue #438](https://github.com/roc-lang/basic-cli/issues/438)).
- TCP connect, read, and write operations require a caller-configured timeout
  covering the whole operation. A zero timeout fails immediately.
  `Tcp.Stream.read_until!` and `read_line!` also require a maximum byte count,
  preventing an untrusted peer from causing unbounded buffering.
- SQLite keeps up to 16 recently used ordinary path connections open. A live
  prepared statement keeps its connection open after cache eviction, and reused
  paths continue sharing that live connection. The exact `:memory:` path is kept
  open for the lifetime of its host thread, so repeated use accesses the same
  in-memory database.

## Examples

The [examples](examples/) directory contains executable, application-shaped CLI
programs for common tasks like reading files, running commands, constructing
URLs, making HTTP requests, working with SQLite, and reading stdin.

The examples are pinned to the [`0.21.0-rc4` release](https://github.com/roc-lang/basic-cli/releases/tag/0.21.0-rc4):

```roc
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0-rc4/FvCh4vdqm3nBY6DWEfZ8RuGCVfjuMY43HA8KSNk9qVDn.tar.zst" }
```

To run examples from a local checkout instead, build the platform first and use `"../platform/main.roc"`; see [CONTRIBUTING.md](CONTRIBUTING.md).

HTTP examples use Roc's builtin `Json` parser and encoder directly through
`Http.get!` and `Http.send_json!`.

## Documentation

- [`0.21.0-rc4` release documentation](https://roc-lang.github.io/basic-cli/0.21.0-rc4/)
- [latest main branch](https://roc-lang.github.io/basic-cli/main/)

## Help

Ask questions on [Roc Zulip](https://roc.zulipchat.com), especially in the `#beginners` stream.

## Contributing

Contributor setup, verification, generated glue, and documentation publishing notes live in [CONTRIBUTING.md](CONTRIBUTING.md).
