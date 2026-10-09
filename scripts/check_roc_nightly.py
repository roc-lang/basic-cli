#!/usr/bin/env python3
"""Check that every pinned Roc nightly (workflows and Nix) is the same."""

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

PATTERNS = {
    ".github/workflows/*.yml": re.compile(r"^\s*nightly-tag:\s*(\S+)\s*$", re.MULTILINE),
    "flake.nix": re.compile(r'rocpkgs\."(nightly-[^"]+)"'),
    "nix/release.nix": re.compile(r'rocpkgs\."(nightly-[^"]+)"'),
}


def find_pins(root: Path) -> dict[str, list[str]]:
    pins: dict[str, list[str]] = {}
    for glob, pattern in PATTERNS.items():
        for path in sorted(root.glob(glob)):
            found = pattern.findall(path.read_text(encoding="utf-8"))
            if found:
                pins[path.relative_to(root).as_posix()] = found
    return pins


def check(root: Path) -> list[str]:
    pins = find_pins(root)
    for glob in PATTERNS:
        if not any(
            Path(name).match(glob) or name == glob for name in pins
        ):
            return [f"no Roc nightly pin found for {glob}"]
    versions = {version for found in pins.values() for version in found}
    if len(versions) == 1:
        return []
    return [f"{name}: {', '.join(found)}" for name, found in pins.items()]


def main() -> int:
    problems = check(ROOT)
    if problems:
        print("Roc nightly pins are not in sync:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print("Roc nightly pins are in sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
