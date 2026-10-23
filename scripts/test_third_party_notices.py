"""Tests for third-party notice generation."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import third_party_notices as notices
from scripts import windows_runtime


def package(directory: Path, name: str, license: str = "MIT", **extra) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "Cargo.toml").write_text("")
    return {"id": name, "name": name, "version": "1.0.0", "license": license,
            "source": "registry+https://github.com/rust-lang/crates.io-index",
            "manifest_path": str(directory / "Cargo.toml"), **extra}


class NoticeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_only_normal_dependencies_are_linked(self):
        def dep(pkg, kind):
            return {"pkg": pkg, "dep_kinds": [{"kind": kind}]}
        metadata = {
            "packages": [{"id": name} for name in ("root", "lib", "transitive", "build", "dev", "build-only")],
            "resolve": {"root": "root", "nodes": [
                {"id": "root", "deps": [dep("lib", None), dep("build", "build"), dep("dev", "dev")]},
                {"id": "lib", "deps": [dep("transitive", None)]},
                {"id": "transitive", "deps": []},
                {"id": "build", "deps": [dep("build-only", None)]},
                {"id": "dev", "deps": []},
                {"id": "build-only", "deps": []},
            ]},
        }
        linked = {p["id"] for p in notices.linked_packages(metadata)}
        self.assertEqual(linked, {"lib", "transitive"})

    def test_license_expressions_must_be_reviewed(self):
        for expression in ("Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT", "Apache-2.0 / MIT",
                           "(MIT OR Apache-2.0) AND Unicode-3.0"):
            notices.check_license({"name": "ok", "version": "1", "license": expression})
        for expression in ("MIT OR GPL-3.0-only", "", None):
            with self.assertRaises(notices.NoticeError):
                notices.check_license({"name": "bad", "version": "1", "license": expression})

    def test_license_files_are_collected_recursively(self):
        crate = package(self.root / "crate", "crate", license_file="legal/TERMS.txt")
        (self.root / "crate" / "LICENSE-MIT").write_text("MIT text  \r\n")
        (self.root / "crate" / "third_party" / "fiat").mkdir(parents=True)
        (self.root / "crate" / "third_party" / "fiat" / "LICENSE").write_text("fiat text")
        (self.root / "crate" / "legal").mkdir()
        (self.root / "crate" / "legal" / "TERMS.txt").write_text("custom terms")
        (self.root / "crate" / "license.rs").write_text("not a license")
        self.assertEqual(notices.license_texts(crate), [
            ("LICENSE-MIT", "MIT text"), ("legal/TERMS.txt", "custom terms"),
            ("third_party/fiat/LICENSE", "fiat text"),
        ])

    def test_package_without_license_files_rejected(self):
        with self.assertRaisesRegex(notices.NoticeError, "No license files"):
            notices.license_texts(package(self.root / "bare", "bare"))

    def test_source_copyrights_come_from_comment_paragraphs(self):
        crate = package(self.root / "crate", "crate")
        (self.root / "crate" / "a.c").write_text(
            "/* Copyright 2015 Example Inc.\n * All rights reserved. */\n\n"
            "/* Unrelated paragraph. */\n#if defined(COPYRIGHT)\n")
        (self.root / "crate" / "b.pl").write_text("#!/usr/bin/env perl\n# Copyright 2016 Perl Author\n")
        (self.root / "crate" / "c.rs").write_text(
            "#![doc = \"copyright\"]\npub const COPYRIGHT: u32 = 1;\n// Adapted from public domain code.\n")
        (self.root / "crate" / "d.rs").write_text("\n" * notices.HEADER_LINES + "// Copyright late\n")
        self.assertEqual(notices.source_copyrights(crate), [
            "Adapted from public domain code.", "Copyright 2015 Example Inc.\nAll rights reserved.",
            "Copyright 2016 Perl Author",
        ])

    def test_code_block_fence_outlasts_backticks(self):
        self.assertEqual(notices.code_block("a ```` b"), "`````text\na ```` b\n`````\n")

    def write_native(self, files: dict[str, bytes], recorded: dict[str, bytes]) -> None:
        for relative, contents in files.items():
            (self.root / relative).parent.mkdir(parents=True, exist_ok=True)
            (self.root / relative).write_bytes(contents)
        (self.root / "licenses").mkdir(exist_ok=True)
        (self.root / "licenses" / "COPYRIGHT.txt").write_text("musl terms")
        hashes = {}
        for relative, contents in recorded.items():
            scratch = self.root / "scratch"
            scratch.write_bytes(contents)
            hashes[relative] = windows_runtime.digest(scratch)
        (self.root / "licenses" / "native-inputs.json").write_text(json.dumps({"components": [{
            "name": "musl libc", "version": "1", "license": "MIT", "license_file": "COPYRIGHT.txt",
            "upstream": "https://example.invalid", "origin": "fixture", "files": hashes,
        }]}))

    def test_recorded_native_inputs_accepted(self):
        files = {"platform/targets/x64musl/libc.a": b"libc", "platform/targets/x64musl/libhost.a": b"host"}
        self.write_native(files, {"platform/targets/x64musl/libc.a": b"libc"})
        self.assertEqual(len(notices.native_components(self.root)), 1)

    def test_changed_native_input_rejected(self):
        self.write_native({"platform/targets/x64musl/libc.a": b"replaced"},
                          {"platform/targets/x64musl/libc.a": b"libc"})
        with self.assertRaisesRegex(notices.NoticeError, "does not match"):
            notices.native_components(self.root)

    def test_unrecorded_native_input_rejected(self):
        self.write_native({"platform/targets/arm64musl/nested/crt1.o": b"crt"}, {})
        with self.assertRaisesRegex(notices.NoticeError, "without a provenance record"):
            notices.native_components(self.root)

    def test_render_groups_identical_texts_and_names_targets(self):
        first = package(self.root / "first", "first", roc_targets=list(notices.RUST_TARGETS))
        second = package(self.root / "second", "second", roc_targets=["x64win"])
        (self.root / "first" / "LICENSE").write_text("Same   terms\n")
        (self.root / "second" / "LICENSE-MIT").write_text("Same\nterms")
        (self.root / "licenses").mkdir()
        (self.root / "licenses" / "COPYRIGHT.txt").write_text("musl terms")
        component = {"name": "musl libc", "version": "1", "license": "MIT", "license_file": "COPYRIGHT.txt",
                     "upstream": "https://example.invalid", "origin": "fixture", "files": {"a.o": "00"}}
        text = notices.render([first, second], [component], "1.0.0", self.root / "licenses")
        self.assertTrue(text.startswith(notices.MARKER))
        self.assertIn("| first | 1.0.0 | MIT | all |", text)
        self.assertIn("| second | 1.0.0 | MIT | x64win |", text)
        self.assertIn("Applies to: first 1.0.0 (`LICENSE`), second 1.0.0 (`LICENSE-MIT`).", text)
        self.assertEqual(text.count("Same"), 1)
        self.assertIn("musl terms", text)

    def test_generated_section_replaces_only_text_after_marker(self):
        with patch.object(notices, "cargo_packages", return_value=[]), \
                patch.object(notices, "native_components", return_value=[]), \
                patch.object(notices, "rust_version", return_value="1.0.0"):
            updated = notices.expected_notices("# Preamble\n\n" + notices.MARKER + "\nstale\n")
            self.assertTrue(updated.startswith("# Preamble\n\n" + notices.MARKER + "\n"))
            self.assertNotIn("stale", updated)
            with self.assertRaisesRegex(notices.NoticeError, "marker"):
                notices.expected_notices("# Preamble without marker\n")


if __name__ == "__main__":
    unittest.main()
