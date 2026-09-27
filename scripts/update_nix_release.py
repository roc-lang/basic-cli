#!/usr/bin/env python3
"""Pin a published platform and its package downloads for offline Nix builds."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def download(url: str, destination: Path) -> str:
    digest = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=60) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    return "sha256-" + base64.b64encode(digest.digest()).decode("ascii")


def package_urls(source: str) -> dict[str, str]:
    block = re.search(r"\bpackages\s*\{([^}]*)\}", source)
    if block is None:
        raise ValueError("Published platform has no packages declaration")
    declarations = re.sub(r"(?m)^\s*#.*$", "", block[1])
    pattern = r'([A-Za-z_][A-Za-z_0-9]*)\s*:\s*"(https://[^"\s]+\.tar\.zst)"\s*,?'
    urls = dict(re.findall(pattern, declarations))
    if re.sub(pattern, "", declarations).strip():
        raise ValueError("Unsupported package declaration; update the Nix dependency pins explicitly")
    return urls


def release_metadata(version: str, url: str) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="basic-cli-nix-release-") as directory:
        archive = Path(directory) / "platform.tar.zst"
        archive_hash = download(url, archive)
        source = subprocess.check_output(
            ["tar", "--zstd", "-xOf", str(archive), "main.roc"], text=True,
        )
        dependencies = {}
        for name, dependency_url in package_urls(source).items():
            dependencies[name] = {
                "url": dependency_url,
                "hash": download(dependency_url, Path(directory) / f"{name}.tar.zst"),
            }
        return {"version": version, "url": url, "hash": archive_hash, "dependencies": dependencies}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "nix/release.json")
    args = parser.parse_args()
    metadata = release_metadata(args.version, args.url)
    args.output.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Pinned basic-cli {args.version} and its package downloads in {args.output}")


if __name__ == "__main__":
    main()
