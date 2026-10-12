"""cc-rs adapter for Zig's GNU-style driver and the MSVC x64 ABI.

Copyright 2026 basic-cli contributors. SPDX-License-Identifier: UPL-1.0
"""
import os
import subprocess
import sys


def compiler_args(args):
    result = []
    skip = False
    for arg in args:
        if skip:
            skip = False
        elif arg == "-target":
            skip = True
        elif not arg.startswith("--target="):
            result.append(arg)
    # Match /MD: use the DLL CRT declarations, without changing the MSVC ABI.
    return ["cc", "-target", "x86_64-windows-msvc", "-fms-runtime-lib=dll", *result]


if __name__ == "__main__":
    raise SystemExit(subprocess.call([os.environ.get("ZIG", "zig"), *compiler_args(sys.argv[1:])]))
