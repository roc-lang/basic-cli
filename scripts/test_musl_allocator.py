#!/usr/bin/env python3
"""Reject per-iteration memory syscalls in small Roc allocations (#530).

Run on native Linux x86_64 with the musl Rust target and strace installed.
This traces the shipped allocator configuration, not a glibc diagnostic host.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

from build import musl_build_env

ROOT = Path(__file__).resolve().parents[1]
TEST = "allocator::tests::repeated_small_roc_allocations_reuse_pages"


def memory_calls(summary: str) -> int:
    count = 0
    seen = False
    for line in summary.splitlines():
        fields = line.split()
        if fields and fields[-1] in {"mmap", "mmap2", "mremap", "munmap", "madvise", "brk"}:
            count += int(fields[3])
            seen = True
    if not seen:
        raise AssertionError(f"strace did not report memory syscalls:\n{summary}")
    return count


def main() -> None:
    if platform.system() != "Linux" or platform.machine() not in {"x86_64", "amd64"}:
        raise SystemExit("Run this regression on native Linux x86_64")
    if not shutil.which("strace"):
        raise SystemExit("Install strace to run the allocator regression")
    build = subprocess.run(
        ["cargo", "test", "--locked", "--release", "--lib", "--no-run",
         "--target", "x86_64-unknown-linux-musl", "--message-format=json"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, check=True,
        env=musl_build_env("x86_64-unknown-linux-musl"),
    )
    executables = []
    for line in build.stdout.splitlines():
        artifact = json.loads(line)
        if (artifact.get("reason") == "compiler-artifact"
                and artifact.get("profile", {}).get("test")
                and artifact.get("executable")):
            executables.append(Path(artifact["executable"]))
    if len(executables) != 1:
        raise AssertionError(f"Expected one host test executable, got {executables}")
    correctness = subprocess.run(
        [str(executables[0]), "--exact",
         "allocator::tests::roc_callbacks_preserve_alignment_and_reallocated_bytes",
         "--nocapture", "--test-threads=1"],
        cwd=ROOT, text=True, stdout=subprocess.PIPE, check=True,
    )
    if "allocator ABI alignment and realloc checks complete" not in correctness.stdout:
        raise AssertionError(f"Allocator ABI test did not execute:\n{correctness.stdout}")
    with tempfile.TemporaryDirectory(prefix="basic-cli-allocator-") as directory:
        for size in (900, 960, 1024, 2048):
            summary = Path(directory) / f"{size}.strace"
            run = subprocess.run(
                ["strace", "-f", "-c", "-qq", "-e", "trace=mmap,mremap,munmap,madvise,brk",
                 "-o", str(summary), str(executables[0]), "--exact", TEST,
                 "--nocapture", "--test-threads=1"],
                cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={**os.environ, "BASIC_CLI_ALLOC_CHURN_INPUT": str(size)}, check=True,
            )
            marker = f"allocator churn complete: input_size={size} iterations=20000"
            if marker not in run.stdout:
                raise AssertionError(f"Churn test did not execute:\n{run.stdout}\n{run.stderr}")
            count = memory_calls(summary.read_text())
            print(f"input={size}: {count} memory syscalls for 20000 iterations", flush=True)
            # Include process/test-harness startup, while rejecting even one
            # memory syscall per 100 iterations. This is independent of machine speed.
            if count > 200:
                raise AssertionError(f"Allocator syscall churn: {count}\n{summary.read_text()}")


if __name__ == "__main__":
    main()
