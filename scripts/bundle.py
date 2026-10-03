#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_DIR = ROOT / "platform"
LIBRARY_EXTENSIONS = {".a", ".o", ".lib", ".obj"}
MAX_PLATFORM_BYTES = 100 * 1024 * 1024


def relative_platform_path(path: Path) -> str:
    return path.relative_to(PLATFORM_DIR).as_posix()


def declared_target_inputs() -> list[Path]:
    """Return every target input file that platform/main.roc declares."""
    header = (PLATFORM_DIR / "main.roc").read_text()
    inputs_dir = re.search(r'inputs_dir:\s*"([^"]+)"', header).group(1)
    inputs = []
    for target, files in re.findall(r"^\s+(\w+):\s*\{\s*inputs:\s*\[([^\]]*)\]", header, re.MULTILINE):
        for name in re.findall(r'"([^"]+)"', files):
            inputs.append(PLATFORM_DIR / inputs_dir / target / name)
    return inputs


def create_placeholders() -> list[Path]:
    """Create empty files for target inputs that were not built.

    `roc bundle` requires every declared target input to exist, but test
    bundles only contain the natively built target.
    """
    created = []
    for path in declared_target_inputs():
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
        created.append(path)
    return created


def main() -> None:
    parser = argparse.ArgumentParser(description="Bundle the basic-cli platform")
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    parser.add_argument(
        "--stub-missing-targets",
        action="store_true",
        help="create empty placeholders for unbuilt targets (test bundles only)",
    )
    args, roc_args = parser.parse_known_args()

    placeholders = create_placeholders() if args.stub_missing_targets else []
    try:
        bundle_platform(args.output_dir, roc_args)
    finally:
        for path in placeholders:
            path.unlink(missing_ok=True)
            try:
                path.parent.rmdir()
            except OSError:
                pass


def bundle_platform(output_dir: Path, roc_args: list[str]) -> None:
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir = output_dir.resolve()

    # `roc bundle` treats the first .roc file as the entry point.
    roc_files = sorted(PLATFORM_DIR.glob("*.roc"), key=lambda path: (path.name != "main.roc", path.name))
    library_files = sorted(
        path
        for path in (PLATFORM_DIR / "targets").rglob("*")
        if path.is_file() and path.suffix in LIBRARY_EXTENSIONS
    )
    bundle_files = [
        *(relative_platform_path(path) for path in roc_files),
        *(relative_platform_path(path) for path in library_files),
    ]
    license_source = ROOT / "THIRD_PARTY_LICENSES.md"
    unpacked_size = sum(path.stat().st_size for path in (*roc_files, *library_files))
    unpacked_size += license_source.stat().st_size
    if unpacked_size > MAX_PLATFORM_BYTES:
        raise SystemExit(
            "Platform inputs exceed Roc's default 100 MiB transitive dependency limit: "
            f"{unpacked_size} bytes"
        )

    print(
        f"Bundling {len(roc_files)} .roc files and "
        f"{len(library_files)} library files...\n"
    )
    print("Files to bundle:")
    for path in bundle_files:
        print(f"  {path}")
    print("  THIRD_PARTY_LICENSES.md\n", flush=True)

    print(f"Unpacked platform size: {unpacked_size} bytes\n")

    license_target = PLATFORM_DIR / "THIRD_PARTY_LICENSES.md"
    shutil.copy2(license_source, license_target)
    try:
        subprocess.run(
            [
                "roc",
                "bundle",
                *bundle_files,
                "THIRD_PARTY_LICENSES.md",
                "--output-dir",
                str(output_dir),
                *roc_args,
            ],
            cwd=PLATFORM_DIR,
            check=True,
        )
    finally:
        license_target.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
