#!/usr/bin/env python3
"""Check Roc/host ownership with a Valgrind-visible glibc diagnostic platform.

The published Linux platform remains static musl. Its allocator is invisible to
Memcheck, so zero reported allocations cannot validate reference-count cleanup.
This Linux x86_64-only check builds an isolated glibc copy under ignored target/.
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
    for name in ("filesystem-tools", "resource-lifetime", "process-control"):
        source = (ROOT / "tests" / "resource-lifetimes" / f"{name}.roc").read_text()
        source, replacements = re.subn(r'platform "[^"]+"', 'platform "platform/main.roc"', source, count=1)
        if replacements != 1:
            raise SystemExit(f"Missing platform declaration in {name}")
        app = work / f"{name}.roc"
        app.write_text(source)
        binary = work / name
        run(roc, "build", str(app), "--target=x64glibc", "--debug", "--no-cache", f"--output={binary}")
        log = work / f"{name}.valgrind.log"
        run("valgrind", "--error-exitcode=99", "--leak-check=full",
            "--errors-for-leak-kinds=definite,indirect", "--track-fds=yes",
            f"--log-file={log}", str(binary), cwd=work)
        text = log.read_text()
        if not re.search(r"total heap usage: [1-9][0-9,]* allocs", text):
            raise SystemExit(f"Valgrind did not observe heap allocations: {log}")
        print(f"Verified native ownership: {log}", flush=True)


if __name__ == "__main__":
    main()
