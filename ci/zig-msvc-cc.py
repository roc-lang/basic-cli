"""cc-rs adapter: GNU-style Zig driver, MSVC ABI, Rust target flags removed."""
import os
import subprocess
import sys

args = []
skip = False
for arg in sys.argv[1:]:
    if skip:
        skip = False
    elif arg == "-target":
        skip = True
    elif not arg.startswith("--target="):
        args.append(arg)
raise SystemExit(subprocess.call([os.environ.get("ZIG", "zig"), "cc", "-target", "x86_64-windows-msvc", *args]))
