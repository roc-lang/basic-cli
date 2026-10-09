#!/usr/bin/env python3
"""Tests for check_roc_nightly.py."""

import tempfile
import unittest
from pathlib import Path

from scripts.check_roc_nightly import check


def write(root: Path, name: str, content: str) -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def fixture(root: Path, workflow: str, flake: str) -> None:
    write(root, ".github/workflows/ci.yml", f"          nightly-tag: {workflow}\n")
    write(root, "flake.nix", f'pkgs.rocpkgs."{flake}"\n')


class CheckRocNightlyTests(unittest.TestCase):
    def problems(self, workflow: str, flake: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture(root, workflow, flake)
            return check(root)

    def test_matching_pins_pass(self) -> None:
        tag = "nightly-2026-10-09-258ab27"
        self.assertEqual(self.problems(tag, tag), [])

    def test_workflow_mismatch_fails(self) -> None:
        tag = "nightly-2026-10-09-258ab27"
        self.assertTrue(self.problems("nightly-2026-10-04-130536d", tag))

    def test_flake_mismatch_fails(self) -> None:
        tag = "nightly-2026-10-09-258ab27"
        self.assertTrue(self.problems(tag, "nightly-2026-09-26-d6267b4"))

    def test_missing_pin_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write(root, ".github/workflows/ci.yml", "nightly-tag: nightly-1\n")
            self.assertTrue(check(root))


if __name__ == "__main__":
    unittest.main()
