#!/usr/bin/env python3
"""Exercise release bump handling with real successful, failing and hung children."""

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.check_version_bump import check_bump


class CheckVersionBumpTests(unittest.TestCase):
    def run_check(self, source: str, **options) -> tuple[int, str, str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = root / "compiler.py"
            compiler.write_text(source, encoding="utf-8")
            output_file = root / "release" / "bump-output.txt"
            stdout, stderr = io.StringIO(), io.StringIO()
            arguments = dict(
                version="0.23.0-rc1", previous_url="https://example.com/0.22.2/pkg.tar.zst",
                entrypoint="platform/main.roc", output_file=output_file,
                timeout_seconds=5, roc_command=(sys.executable, str(compiler)),
            )
            arguments.update(options)
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = check_bump(**arguments)
            return status, output_file.read_text(), stdout.getvalue() + stderr.getvalue()

    def test_success_uses_base_version_and_preserves_output(self):
        for mode in ("warn", "require"):
            with self.subTest(mode=mode):
                status, output, log = self.run_check(
                    "import sys\nassert sys.argv[1:] == ['bump', '--old', "
                    "'https://example.com/0.22.2/pkg.tar.zst', '--expect', '0.23.0', "
                    "'platform/main.roc']\nprint('API comparison passed')\n", mode=mode,
                )
                self.assertEqual(status, 0)
                self.assertIn("API comparison passed", output)
                self.assertIn("API comparison passed", log)

    def test_failure_warns_or_requires(self):
        for mode, expected in (("warn", 0), ("require", 1)):
            with self.subTest(mode=mode):
                status, output, log = self.run_check(
                    "import sys\nprint('extraction failed', file=sys.stderr)\nsys.exit(7)\n",
                    mode=mode,
                )
                self.assertEqual(status, expected)
                self.assertIn("extraction failed", output)
                self.assertIn("status 7", output)
                self.assertIn("warning:" if mode == "warn" else "error:", log)

    def test_timeout_retains_partial_output(self):
        for mode, expected in (("warn", 0), ("require", 1)):
            with self.subTest(mode=mode):
                status, output, log = self.run_check(
                    "import time\nprint('starting comparison', flush=True)\ntime.sleep(60)\n",
                    mode=mode, timeout_seconds=1,
                )
                self.assertEqual(status, expected)
                self.assertIn("starting comparison", output)
                self.assertIn("timed out", output)
                self.assertIn("timed out", log)

    def test_dry_run_and_off_do_not_start_compiler(self):
        for options in ({"dry_run": True, "mode": "require"}, {"mode": "off"}):
            with self.subTest(options=options):
                status, output, _ = self.run_check("raise AssertionError('must not run')", **options)
                self.assertEqual(status, 0)
                self.assertTrue(output.startswith("roc bump check skipped"))

    def test_missing_previous_release(self):
        for mode, expected in (("warn", 0), ("require", 1)):
            status, output, _ = self.run_check("raise AssertionError('must not run')", previous_url="", mode=mode)
            self.assertEqual(status, expected)
            self.assertIn("No previous release", output)

    def test_missing_compiler_obeys_mode(self):
        for mode, expected in (("warn", 0), ("require", 1)):
            status, output, _ = self.run_check("", roc_command=("/nonexistent/roc",), mode=mode)
            self.assertEqual(status, expected)
            self.assertIn("Could not run roc bump", output)


if __name__ == "__main__":
    unittest.main()
