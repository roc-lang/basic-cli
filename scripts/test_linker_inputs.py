import concurrent.futures
import hashlib
import io
import json
import subprocess
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from scripts import linker_inputs as inputs


class LinkerInputTests(unittest.TestCase):
    def test_runtime_binaries_are_not_tracked(self):
        tracked = subprocess.check_output(["git", "ls-files", "-z", "platform/targets"],
                                          cwd=inputs.ROOT).decode().split("\0")
        binaries = [name for name in tracked if Path(name).suffix.lower() in inputs.windows_runtime.BINARY_EXTENSIONS]
        self.assertEqual(binaries, [], "Runtime binaries belong in linker-input releases")

    def test_installed_runtime_checks_exclude_source_built_host(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {}
            for name in inputs.INVENTORY["x64musl"]:
                path = root / name
                path.write_bytes(name.encode())
                files[name] = {"sha256": inputs.sha256(path), "size": path.stat().st_size}
            (root / "LINKER_INPUTS.json").write_bytes(inputs.canonical({"format_version": 1, "target": "x64musl", "files": files}))
            (root / "libhost.a").write_bytes(b"source build")
            inputs.installed_documents(root, "x64musl")
            (root / "old-crt.o").write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError, "binary inventory"):
                inputs.installed_documents(root, "x64musl")

    def test_cache_survives_offline_and_repairs_corruption(self):
        data = b"verified archive bytes"
        record = {"url": "https://example.invalid/inputs", "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            with patch.object(inputs.urllib.request, "urlopen", return_value=io.BytesIO(data)) as request:
                cached = inputs.download(record, cache)
                self.assertEqual(cached.read_bytes(), data)
                self.assertEqual(request.call_count, 1)
            with patch.object(inputs.urllib.request, "urlopen", side_effect=AssertionError("network used")):
                self.assertEqual(inputs.download(record, cache), cached)
                with self.assertRaisesRegex(ValueError, "size mismatch"):
                    inputs.download({**record, "size": len(data) + 1}, cache)
            cached.write_bytes(b"corrupt")
            with patch.object(inputs.urllib.request, "urlopen", return_value=io.BytesIO(data)):
                self.assertEqual(inputs.download(record, cache).read_bytes(), data)

    def test_wrong_download_never_enters_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            record = {"url": "https://example.invalid/inputs", "sha256": "0" * 64}
            with patch.object(inputs.urllib.request, "urlopen", return_value=io.BytesIO(b"wrong")):
                with self.assertRaisesRegex(ValueError, "Checksum"):
                    inputs.download(record, cache)
            self.assertEqual([p for p in cache.iterdir() if p.suffix != ".lock"], [])

    def test_concurrent_fetches_publish_only_verified_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            source = cache / "source"
            source.write_bytes(b"concurrent content")
            record = {"url": source.as_uri(), "sha256": inputs.sha256(source)}
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
                paths = list(executor.map(lambda _: inputs.download(record, cache), range(8)))
            self.assertEqual(len(set(paths)), 1)
            self.assertEqual(paths[0].read_bytes(), source.read_bytes())

    def test_archive_rejects_escape_links_and_duplicate_names(self):
        for name, kind in [("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                           ("C:/escape", tarfile.REGTYPE), ("link", tarfile.SYMTYPE),
                           ("a/../escape", tarfile.REGTYPE), ("duplicate", tarfile.REGTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "test.tar"
                with tarfile.open(archive, "w") as packed:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    packed.addfile(entry, io.BytesIO())
                    if name == "duplicate":
                        packed.addfile(entry, io.BytesIO())
                with self.assertRaisesRegex(ValueError, "Invalid archive"):
                    inputs.unpack(archive, root / "out")

    def test_failed_restore_preserves_existing_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destination = root / "target"
            destination.mkdir()
            (destination / "libhost.a").write_bytes(b"existing host")
            archive = root / "invalid.tar"
            data = inputs.canonical({"format_version": 1, "target": "arm64musl"})
            with tarfile.open(archive, "w") as packed:
                entry = tarfile.TarInfo("LINKER_INPUTS.json")
                entry.size = len(data)
                packed.addfile(entry, io.BytesIO(data))
            lock = root / "lock.json"
            lock.write_bytes(inputs.canonical({"targets": {"x64musl": {
                "url": archive.as_uri(), "sha256": inputs.sha256(archive)}}}))
            with self.assertRaisesRegex(ValueError, "manifest target"):
                inputs.restore("x64musl", destination, cache=root / "cache", lock=lock)
            self.assertEqual([p.name for p in destination.iterdir()], ["libhost.a"])
            self.assertEqual((destination / "libhost.a").read_bytes(), b"existing host")
            self.assertEqual(list(root.glob(".linker-inputs-*")), [])

    def test_inventory_and_file_hashes_are_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {}
            for name in inputs.INVENTORY["x64musl"]:
                path = root / name
                path.write_bytes(name.encode())
                files[name] = {"sha256": inputs.sha256(path), "size": path.stat().st_size}
            (root / "LINKER_INPUTS.json").write_bytes(inputs.canonical({"format_version": 1, "target": "x64musl", "files": files}))
            inputs.verify(root, "x64musl")
            (root / "libc.a").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "file mismatch"):
                inputs.verify(root, "x64musl")
            with self.assertRaisesRegex(ValueError, "target or format"):
                inputs.verify(root, "arm64musl")


if __name__ == "__main__":
    unittest.main()
