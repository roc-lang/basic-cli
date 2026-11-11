#!/usr/bin/env python3
"""Verify Linux platform executables have no loader or shared dependencies."""
import argparse
from pathlib import Path
import subprocess


def check(directory: Path, *, pie: bool) -> None:
    binaries = [p for p in directory.iterdir() if p.is_file() and p.read_bytes()[:4] == b"\x7fELF"]
    if not binaries:
        raise ValueError(f"No ELF executables in {directory}")
    for binary in binaries:
        headers = subprocess.check_output(["readelf", "-h", "-l", "-d", str(binary)], text=True)
        if any(tag in headers for tag in ("INTERP", "NEEDED", "TEXTREL")):
            raise ValueError(f"{binary} has a loader, shared dependency, or text relocation")
        expected = "DYN (Position-Independent Executable file)" if pie else "EXEC (Executable file)"
        if expected not in headers:
            raise ValueError(f"{binary} does not have expected ELF type {expected}")
    if pie and (directory / "stdin-pipe").is_file():
        check_aslr(directory / "stdin-pipe")
    print(f"Verified {len(binaries)} fully static {'PIE' if pie else 'fixed-address'} executables")


def check_aslr(binary: Path) -> None:
    if Path("/proc/sys/kernel/randomize_va_space").read_text().strip() == "0":
        raise ValueError("ASLR must be enabled to validate randomized loading")
    addresses = set()
    binary = binary.resolve()
    for _ in range(4):
        with subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE) as process:
            try:
                mappings = Path(f"/proc/{process.pid}/maps").read_text().splitlines()
                bases = [int(line.split()[0].split("-")[0], 16) - int(line.split()[2], 16)
                         for line in mappings if line.endswith(str(binary))]
                if not bases:
                    raise ValueError("Could not observe the running executable's mappings")
                addresses.add(min(bases))
                _, errors = process.communicate(b"runtime input check\n", timeout=20)
                if process.returncode:
                    raise ValueError(f"ASLR execution failed: {errors!r}")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
    if len(addresses) < 2:
        raise ValueError("PIE executable loaded at a fixed address across independent launches")
    print("Verified randomized executable load addresses across four launches")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--format", choices=("pinned", "pie"), required=True)
    args = parser.parse_args()
    check(args.directory, pie=args.format == "pie")
