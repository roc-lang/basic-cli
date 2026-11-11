# Linker inputs

The Linker inputs workflow builds runtime archives independently of the Rust
host. Run it manually on the default branch to publish a content-addressed
prerelease. The attached `linker-inputs.lock.json` pins each target archive by
URL, SHA-256, and size. Platform builds will consume that lock after migration.

The producer pins musl 1.2.6's source archive and Zig 0.17.0's libunwind source
tree. Linux libraries are PIC and use baseline CPUs. The recorded musl change
allows an absent dynamic section in `rcrt1.o`, supporting fixed-address static
executables as well as static PIE. Native producer checks exercise both forms,
including stored function pointers, thread-local data, and threads.

Windows uses the existing source-verified startup and import-library producer.
Its native check exercises initializer tables, TLS, security cookies, and
MSVC type-info support. Source hashes and original licenses accompany each
archive. Rust host libraries are built by the platform consumer workflows.

For local production, use Python 3.12, Zig 0.17.0, and GNU make. Linux native
checks also use the platform GNU linker and readelf. For example,

```sh
python3 scripts/linker_inputs.py build --target x64musl --directory dist/linker-inputs
```

Publication requires each target to have passed validation on its native OS and
architecture. The workflow publishes only after all three producers succeed.
