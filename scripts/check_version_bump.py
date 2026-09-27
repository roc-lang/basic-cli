#!/usr/bin/env python3
"""Run the release API comparison with a bounded wait and durable diagnostics."""

import argparse
import math
import subprocess
import sys
from pathlib import Path


def check_bump(
    *,
    version: str,
    previous_url: str,
    entrypoint: str,
    output_file: Path,
    mode: str = "warn",
    dry_run: bool = False,
    timeout_seconds: float = 120,
    roc_command: tuple[str, ...] = ("roc",),
) -> int:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    if dry_run or mode == "off":
        reason = "dry-run release" if dry_run else "bump_check is off"
        output_file.write_text(f"roc bump check skipped because {reason}.\n", encoding="utf-8")
        return 0

    failure = None
    # The release workflow validates the full version before this step. roc bump
    # compares the base semver, including when publishing a prerelease.
    base_version = version.split("-", 1)[0].split("+", 1)[0]
    with output_file.open("w", encoding="utf-8") as output:
        if not previous_url:
            failure = "No previous release bundle found; roc bump check skipped."
        else:
            try:
                result = subprocess.run(
                    [*roc_command, "bump", "--old", previous_url,
                     "--expect", base_version, entrypoint],
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    timeout=timeout_seconds,
                    check=False,
                )
                if result.returncode != 0:
                    failure = f"roc bump exited with status {result.returncode}."
            except subprocess.TimeoutExpired:
                # subprocess.run kills and reaps the compiler before returning.
                # Writing straight to the file retains diagnostics from a hang.
                failure = f"roc bump timed out after {timeout_seconds:g} seconds."
            except OSError as error:
                failure = f"Could not run roc bump: {error}"
        if failure:
            output.write(f"\n{failure}\n")

    diagnostic = output_file.read_text(encoding="utf-8", errors="replace")
    if diagnostic:
        print(diagnostic, end="" if diagnostic.endswith("\n") else "\n")
    if failure:
        level = "warning" if mode == "warn" else "error"
        print(f"{level}: {failure}", file=sys.stderr)
        return 0 if mode == "warn" else 1
    return 0


def positive_seconds(value: str) -> float:
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("timeout must be a positive finite number")
    return seconds


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--previous-url", default="")
    parser.add_argument("--entrypoint", default="platform/main.roc")
    parser.add_argument("--output-file", type=Path, default=Path(".release/bump-output.txt"))
    parser.add_argument("--mode", choices=("warn", "require", "off"), default="warn")
    parser.add_argument("--dry-run", choices=("true", "false"), default="false")
    parser.add_argument("--timeout-seconds", type=positive_seconds, default=120)
    args = vars(parser.parse_args())
    args["dry_run"] = args["dry_run"] == "true"
    return check_bump(**args)


if __name__ == "__main__":
    sys.exit(main())
