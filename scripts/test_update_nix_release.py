"""Release pins must follow the published archive, not the current checkout."""
import base64
import hashlib
import io
import subprocess
import tarfile
import unittest
from unittest.mock import patch

from scripts.update_nix_release import package_urls, release_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def test_downloaded_archive_controls_dependencies_and_hashes(self):
        platform_url = "https://example.test/platform.tar.zst"
        http_url = "https://example.test/http-v2.tar.zst"
        source = f'platform "" packages {{ http: "{http_url}", }}'.encode()
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w") as tar:
            info = tarfile.TarInfo("main.roc")
            info.size = len(source)
            tar.addfile(info, io.BytesIO(source))
        compressed = subprocess.check_output(["zstd", "-q", "-c"], input=archive.getvalue())
        downloads = {platform_url: compressed, http_url: b"http package"}

        def open_url(url, timeout):
            self.assertGreater(timeout, 0)
            return io.BytesIO(downloads[url])

        with patch("scripts.update_nix_release.urllib.request.urlopen", side_effect=open_url):
            metadata = release_metadata("0.24.0", platform_url)
        self.assertEqual(metadata["version"], "0.24.0")
        self.assertEqual(metadata["url"], platform_url)
        for entry in [metadata, metadata["dependencies"]["http"]]:
            expected = base64.b64encode(hashlib.sha256(downloads[entry["url"]]).digest()).decode()
            self.assertEqual(entry["hash"], "sha256-" + expected)

    def test_unsupported_dependencies_are_not_silently_omitted(self):
        with self.assertRaises(ValueError):
            package_urls('platform "" packages { local: "../local/main.roc" }')
        with self.assertRaises(ValueError):
            package_urls('platform ""')

    def test_comments_and_empty_packages(self):
        self.assertEqual(package_urls('platform "" packages {\n # no dependencies\n }'), {})


if __name__ == "__main__":
    unittest.main()
