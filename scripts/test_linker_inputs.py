import concurrent.futures
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from scripts import linker_inputs as inputs


class LinkerInputTests(unittest.TestCase):
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
                           ("a/../escape", tarfile.REGTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "test.tar"
                with tarfile.open(archive, "w") as packed:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    packed.addfile(entry, io.BytesIO())
                with self.assertRaisesRegex(ValueError, "Invalid archive"):
                    inputs.unpack(archive, root / "out")

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
