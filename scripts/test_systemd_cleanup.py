#!/usr/bin/env python3
"""Exercise the default systemctl stop SIGTERM against the built Roc fixture.

Run on a Linux system with systemd as its service manager (CI invokes with sudo).
The file models an external resource; stopping must leave it cleaned, not acquired.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    binary.chmod(binary.stat().st_mode | 0o111)
    unit = f"basic-cli-cleanup-{uuid.uuid4().hex}.service"
    with tempfile.TemporaryDirectory(prefix="basic-cli-systemd-") as directory:
        marker = Path(directory) / "resource-state.txt"
        try:
            # Keep KillSignal and KillMode at systemd defaults. This is the
            # actual service stop path rather than a direct kill(pid, SIGTERM).
            runner = subprocess.Popen(
                ["systemd-run", "--wait", "--unit", unit, "--property", "Type=exec",
                 "--property", "TimeoutStopSec=10s", "--working-directory", directory,
                 str(binary), "service"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            deadline = time.monotonic() + 10
            while not marker.exists() or marker.read_text() != "acquired":
                if runner.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError("Service did not acquire its resource")
                time.sleep(0.02)
            run("systemctl", "stop", unit)
            assert marker.read_text() == "cleaned", "Stop skipped application cleanup"
            # --wait retains the result even if the inactive transient unit
            # is unloaded before a later `systemctl show` could inspect it.
            output, _ = runner.communicate(timeout=10)
            assert runner.returncode == 0, output
            print("Default systemctl stop completed Roc application cleanup")
        finally:
            subprocess.run(["systemctl", "stop", unit], check=False, capture_output=True)
            subprocess.run(["systemctl", "reset-failed", unit], check=False, capture_output=True)
            if "runner" in locals() and runner.poll() is None:
                runner.kill()
                runner.communicate()


if __name__ == "__main__":
    main()
