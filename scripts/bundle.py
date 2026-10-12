#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
from pathlib import Path

try:
    from . import windows_runtime
except ImportError:
    import windows_runtime


ROOT = Path(__file__).resolve().parents[1]
PLATFORM_DIR = ROOT / "platform"
LIBRARY_EXTENSIONS = windows_runtime.BINARY_EXTENSIONS
MAX_PLATFORM_BYTES = 100 * 1024 * 1024


def relative_platform_path(path: Path) -> str:
    return path.relative_to(PLATFORM_DIR).as_posix()


def declared_target_inputs() -> list[Path]:
    source = (PLATFORM_DIR / "main.roc").read_text(encoding="utf-8")
    inputs: list[Path] = []
    for target, files in re.findall(r"^\s*(\w+):\s*\{\s*inputs:\s*\[(.*)\]", source, re.MULTILINE):
        for name in re.findall(r'"([^"]+)"', files):
            inputs.append(PLATFORM_DIR / "targets" / target / name)
    return inputs


def main() -> None:
    parser = argparse.ArgumentParser(description="Bundle the basic-cli platform")
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    parser.add_argument(
        "--stub-missing-targets",
        action="store_true",
        help="create empty placeholders for unbuilt target inputs (local test bundles only)",
    )
    args, roc_args = parser.parse_known_args()

    # `roc bundle` requires every declared target input to exist. Test bundles
    # only need the native host, so other targets get temporary empty files.
    stubs: list[Path] = []
    if args.stub_missing_targets:
        for path in declared_target_inputs():
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.touch()
                stubs.append(path)
    try:
        bundle(args, roc_args)
    finally:
        for path in stubs:
            path.unlink(missing_ok=True)


def bundle(args: argparse.Namespace, roc_args: list[str]) -> None:

    output_dir = args.output_dir
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    output_dir = output_dir.resolve()

    # `roc bundle` treats the first file as the platform entry point.
    roc_files = sorted(
        PLATFORM_DIR.glob("*.roc"), key=lambda path: (path.name != "main.roc", path.name)
    )
    library_files = sorted(
        path
        for path in (PLATFORM_DIR / "targets").rglob("*")
        if path.is_file() and path.suffix.lower() in LIBRARY_EXTENSIONS
    )
    declared = declared_target_inputs()
    if not args.stub_missing_targets:
        missing = [relative_platform_path(p) for p in declared if not p.is_file() or not p.stat().st_size]
        if missing:
            raise SystemExit(f"Missing or empty platform inputs: {', '.join(missing)}")
    windows_dir = PLATFORM_DIR / "targets" / "x64win"
    windows_inputs = [windows_dir / name for name in (*windows_runtime.LIBRARIES, "host.lib")]
    stubbed_windows = args.stub_missing_targets and any(
        not p.is_file() or not p.stat().st_size for p in windows_inputs
    )
    metadata_files = [] if stubbed_windows else windows_runtime.validate(windows_dir)
    bundle_files = [
        *(relative_platform_path(path) for path in roc_files),
        *(relative_platform_path(path) for path in library_files),
        *(relative_platform_path(path) for path in metadata_files),
    ]
    license_sources = [ROOT / "THIRD_PARTY_LICENSES.md", ROOT / "LICENSE"]
    unpacked_size = sum(path.stat().st_size for path in (*roc_files, *library_files, *metadata_files, *license_sources))
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
    for path in license_sources:
        print(f"  {path.name}", flush=True)

    print(f"Unpacked platform size: {unpacked_size} bytes\n")

    backups = {}
    try:
        for source in license_sources:
            destination = PLATFORM_DIR / source.name
            backups[destination] = destination.read_bytes() if destination.exists() else None
            shutil.copy2(source, destination)
        subprocess.run(
            [
                "roc",
                "bundle",
                *bundle_files,
                *(path.name for path in license_sources),
                "--output-dir",
                str(output_dir),
                *roc_args,
            ],
            cwd=PLATFORM_DIR,
            check=True,
        )
    finally:
        for destination, contents in backups.items():
            if contents is None:
                destination.unlink(missing_ok=True)
            else:
                destination.write_bytes(contents)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
