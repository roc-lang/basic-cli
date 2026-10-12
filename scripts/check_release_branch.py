#!/usr/bin/env python3
"""Keep stable publications on the default branch; allow branch RCs."""
import argparse
import re


def check_release_branch(version: str, ref_type: str, ref_name: str, default_branch: str) -> None:
    if ref_type != "branch":
        raise ValueError("Releases must be dispatched from a branch")
    if ref_name != default_branch and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+-rc[1-9][0-9]*", version):
        raise ValueError("Only X.Y.Z-rcN release candidates may be published from a non-default branch")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("version", "ref-type", "ref-name", "default-branch"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    try:
        check_release_branch(args.version, args.ref_type, args.ref_name, args.default_branch)
    except ValueError as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
