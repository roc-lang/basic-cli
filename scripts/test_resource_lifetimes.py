#!/usr/bin/env python3
"""Check Roc/host ownership with a Valgrind-visible glibc diagnostic platform.

The published Linux platform uses static musl and mimalloc. Its allocator is invisible to
Memcheck, so zero reported allocations cannot validate reference-count cleanup.
This Linux x86_64-only check builds an isolated glibc copy under ignored target/.

Memcheck cannot see a leaked resource handle. Handle boxes live in the host's
own typed heaps (src/resources.rs), which are mapped rather than malloc'd, and
the native value behind a leaked handle stays reachable from its slot. Each run
therefore also sets BASIC_CLI_LIVE_HANDLES and requires the host to report zero
live handles; scripts/test_spec.json makes the same assertion on every OS.
Valgrind still covers everything else: memory errors, ordinary Roc allocations,
and native values that are destroyed without being freed.
"""
from __future__ import annotations

import os
from pathlib import Path
import platform
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(*args: str, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    print("+", *args, flush=True)
    return subprocess.run(args, cwd=cwd, text=True, check=True)


def main() -> None:
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise SystemExit("This diagnostic requires x86_64 Linux with glibc")
    if not shutil.which("valgrind"):
        raise SystemExit("Install Valgrind to run the resource-lifetime diagnostic")
    roc = os.environ.get("ROC", "roc")
    work = ROOT / "target" / "resource-lifetimes-glibc"
    pf = work / "platform"
    inputs = pf / "targets" / "x64glibc"
    inputs.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / "platform").glob("*.roc"):
        shutil.copy2(source, pf / source.name)
    main_path = pf / "main.roc"
    main_path.write_text(main_path.read_text().replace(
        'inputs_dir: "targets/",',
        'inputs_dir: "targets/",\n'
        '        x64glibc: { inputs: ["Scrt1.o", "crti.o", "libhost.a", app, '
        '"crtn.o", "libc.so", "libgcc_s.so.1", "libm.so.6"] },',
    ))
    for name in ("Scrt1.o", "crti.o", "crtn.o", "libc.so", "libgcc_s.so.1", "libm.so.6"):
        source = Path("/usr/lib/x86_64-linux-gnu") / name
        if not source.is_file():
            raise SystemExit(f"Missing glibc development input: {source}")
        shutil.copy2(source, inputs / name)
    run("cargo", "build", "--locked", "--lib", "--target", "x86_64-unknown-linux-gnu")
    shutil.copy2(ROOT / "target/x86_64-unknown-linux-gnu/debug/libhost.a", inputs / "libhost.a")
    for name in (
        "filesystem-tools", "resource-lifetime", "process-control",
        "binary-file-reader", "binary-file-chunks",
    ):
        source = (ROOT / "tests" / "resource-lifetimes" / f"{name}.roc").read_text()
        source, replacements = re.subn(r'platform "[^"]+"', 'platform "platform/main.roc"', source, count=1)
        if replacements != 1:
            raise SystemExit(f"Missing platform declaration in {name}")
        app = work / f"{name}.roc"
        app.write_text(source)
        binary = work / name
        run(roc, "build", str(app), "--target=x64glibc", "--debug", "--no-cache", f"--output={binary}")
        log = work / f"{name}.valgrind.log"
        command = (
            "valgrind", "--error-exitcode=99", "--leak-check=full",
            "--errors-for-leak-kinds=definite,indirect", "--track-fds=yes",
            f"--log-file={log}", str(binary),
        )
        print("+", *command, flush=True)
        result = subprocess.run(
            command, cwd=work, text=True, check=True, stderr=subprocess.PIPE,
            env={**os.environ, "BASIC_CLI_LIVE_HANDLES": "1"},
        )
        print(result.stderr, end="", flush=True)
        # Child processes inherit the variable and may report too.
        reports = re.findall(r"^live handles: (\d+)$", result.stderr, re.MULTILINE)
        if not reports or any(count != "0" for count in reports):
            raise SystemExit(f"{name}: resource handles were still live at exit")
        text = log.read_text()
        if not re.search(r"total heap usage: [1-9][0-9,]* allocs", text):
            raise SystemExit(f"Valgrind did not observe heap allocations: {log}")
        print(f"Verified native ownership: {log}", flush=True)


if __name__ == "__main__":
    main()
