#!/usr/bin/env python3
"""Build, verify, and restore independently released native runtime inputs."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import platform
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

try:
    from . import windows_runtime
except ImportError:
    import windows_runtime

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / "native/linker-inputs/recipe.json"
LOCK = ROOT / "linker-inputs.lock.json"
INVENTORY = {
    "x64musl": {"rcrt1.o", "libc.a", "libunwind.a"},
    "arm64musl": {"rcrt1.o", "libc.a", "libunwind.a"},
    "x64win": {"windows_support.lib"},
}


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


def sha256(path: Path) -> str:
    return windows_runtime.digest(path)


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file():
            digest.update(path.relative_to(root).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def cache_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") if os.name == "nt" else os.environ.get("XDG_CACHE_HOME")
    return (Path(base) if base else Path.home() / ".cache") / "basic-cli/linker-inputs"


def download(record: dict, cache: Path) -> Path:
    digest = record["sha256"]
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Invalid linker-input SHA-256")
    cache.mkdir(parents=True, exist_ok=True)
    destination = cache / digest
    if destination.is_file() and sha256(destination) == digest:
        return destination
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            with urllib.request.urlopen(record["url"], timeout=120) as source:
                shutil.copyfileobj(source, temporary)
            temporary.flush()
            if sha256(pending) != digest:
                raise ValueError(f"Checksum mismatch downloading {record['url']}")
            if "size" in record and pending.stat().st_size != record["size"]:
                raise ValueError("Linker-input size mismatch")
            os.replace(pending, destination)
        finally:
            pending.unlink(missing_ok=True)
    return destination


def unpack(archive: Path, destination: Path) -> None:
    """Extract regular files only, rejecting ambiguous or escaping members."""
    with tarfile.open(archive) as packed:
        seen: set[str] = set()
        for entry in packed:
            path = PurePosixPath(entry.name)
            if (not entry.isfile() or path.is_absolute() or ".." in path.parts
                    or "\\" in entry.name or ":" in entry.name or str(path) != entry.name
                    or entry.name in seen):
                raise ValueError(f"Invalid archive member: {entry.name}")
            seen.add(entry.name)
            target = destination / entry.name
            target.parent.mkdir(parents=True, exist_ok=True)
            source = packed.extractfile(entry)
            if source is None:
                raise ValueError(f"Missing archive member: {entry.name}")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)


def verify(directory: Path, target: str) -> dict:
    manifest = json.loads((directory / "LINKER_INPUTS.json").read_bytes())
    if manifest.get("format_version") != 1 or manifest.get("target") != target:
        raise ValueError("Linker-input manifest target or format mismatch")
    actual = {p.relative_to(directory).as_posix() for p in directory.rglob("*") if p.is_file()}
    if actual != set(manifest["files"]) | {"LINKER_INPUTS.json"}:
        raise ValueError("Linker-input inventory mismatch")
    binaries = {name for name in actual if Path(name).suffix in windows_runtime.BINARY_EXTENSIONS}
    if binaries != INVENTORY[target]:
        raise ValueError("Unexpected linker-input binaries")
    for name, record in manifest["files"].items():
        path = directory / name
        if path.is_symlink() or sha256(path) != record["sha256"] or path.stat().st_size != record["size"]:
            raise ValueError(f"Linker-input file mismatch: {name}")
    if target == "x64win":
        windows_runtime.validate(directory, require_host=False)
    return manifest


def restore(target: str, destination: Path, *, cache: Path | None = None, lock: Path = LOCK) -> None:
    record = json.loads(lock.read_bytes())["targets"][target]
    archive = download(record, cache or cache_dir())
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix=".linker-inputs-") as temporary:
        stage = Path(temporary)
        unpack(archive, stage)
        verify(stage, target)
        # Copy verified runtime files only. Host outputs belong to the source build.
        for path in stage.rglob("*"):
            if path.is_file():
                output = destination / path.relative_to(stage)
                output.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary_file:
                    pending = Path(temporary_file.name)
                try:
                    shutil.copyfile(path, pending)
                    os.replace(pending, output)
                finally:
                    pending.unlink(missing_ok=True)


def run(args: list[str], **kwargs) -> None:
    subprocess.run(args, check=True, **kwargs)


def build_linux(target: str, output: Path, work: Path, zig: str, recipe: dict, jobs: int) -> None:
    triple = recipe["targets"][target]
    source_archive = download(recipe["musl"], cache_dir() / "sources")
    with tarfile.open(source_archive) as archive:
        archive.extractall(work, filter="data")
    source = work / ("musl-" + recipe["musl"]["version"])
    loader = source / "ldso/dlstart.c"
    contents = loader.read_text()
    old = "for (i=0; dynv[i]; i+=2) if (dynv[i]<DYN_CNT)"
    if contents.count(old) != 1:
        raise ValueError("musl startup source differs from the reviewed patch")
    loader.write_text(contents.replace(old, "for (i=0; dynv && dynv[i]; i+=2) if (dynv[i]<DYN_CNT)"))
    environment = dict(os.environ, CC=f"{zig} cc -target {triple} -mcpu=baseline -fno-sanitize=all",
                       AR=f"{zig} ar", RANLIB=f"{zig} ranlib", LC_ALL="C",
                       CFLAGS=f"-O2 -fPIC -ffile-prefix-map={work}=/build")
    build = work / "musl-build"
    build.mkdir()
    run([str(source / "configure"), "--disable-shared", "--prefix=/usr"], cwd=build, env=environment)
    run(["make", f"-j{jobs}", "lib/libc.a", "lib/rcrt1.o"], cwd=build, env=environment)
    for name in ("libc.a", "rcrt1.o"):
        shutil.copyfile(build / "lib" / name, output / name)
    licenses = output / "licenses"
    licenses.mkdir()
    shutil.copyfile(source / "COPYRIGHT", licenses / "musl-COPYRIGHT.txt")
    zig_lib = windows_runtime.zig_lib_dir(zig)
    unwind = zig_lib / "libunwind"
    if tree_hash(unwind) != recipe["unwind"]["tree_sha256"]:
        raise ValueError("Zig libunwind sources differ from the recipe")
    # An isolated toolchain cache contains exactly one generated target unwinder.
    environment = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(work / "zig-cache"),
                       ZIG_LOCAL_CACHE_DIR=str(work / "zig-local"))
    probe = ROOT / "native/linker-inputs/unwind.cpp"
    run([zig, "c++", "-target", triple, "-mcpu=baseline", "-fPIC", "-static", "-O2", "-g0",
         str(probe), "-o", str(work / "unwind-probe")], env=environment)
    archives = list((work / "zig-cache/o").glob("*/libunwind.a"))
    if len(archives) != 1:
        raise ValueError("Expected one freshly built libunwind archive")
    shutil.copyfile(archives[0], output / "libunwind.a")
    shutil.copyfile(unwind / "LICENSE.TXT", licenses / "libunwind-LICENSE.TXT")
    shutil.copyfile(zig_lib.parent / "LICENSE", licenses / "zig-LICENSE.txt")


def validate_native(target: str, output: Path, work: Path, zig: str, recipe: dict) -> bool:
    expected = {"x64musl": ("Linux", "x86_64"), "arm64musl": ("Linux", "aarch64"),
                "x64win": ("Windows", "amd64")}
    system, machine = expected[target]
    if platform.system() != system or platform.machine().lower() != machine:
        return False
    if target == "x64win":
        obj = work / "fixture.obj"
        exe = work / "fixture.exe"
        run([zig, "cc", "-target", recipe["targets"][target], "-O2", "-fstack-protector-strong",
             "-c", str(ROOT / "native/windows/runtime_fixture.c"), "-o", str(obj)])
        run([zig, "lld-link", "/nodefaultlib", "/subsystem:console", "/entry:mainCRTStartup",
             "/machine:x64", "/dynamicbase", "/fixed:no", "/highentropyva", "/opt:ref",
             f"/out:{exe}", str(obj), str(output / "windows_support.lib")])
        result = subprocess.run([str(exe), "a b"], timeout=20, check=False)
        if result.returncode != 37:
            raise ValueError("Windows runtime startup/TLS validation failed")
        return True
    obj = work / "startup.o"
    run([zig, "cc", "-target", recipe["targets"][target], "-fPIC", "-O2", "-c",
         str(ROOT / "native/linker-inputs/startup.c"), "-o", str(obj)])
    for flag, elf_type in (("-no-pie", "EXEC"), ("-pie", "DYN")):
        exe = work / ("startup" + flag)
        run(["ld", "-static", flag, "--no-dynamic-linker", "-z", "text",
             str(output / "rcrt1.o"), str(obj), str(output / "libc.a"), "-o", str(exe)])
        result = subprocess.check_output([str(exe)], text=True, timeout=20)
        if result != "startup passed\n":
            raise ValueError("Static startup/TLS validation failed")
        elf = subprocess.check_output(["readelf", "-h", "-l", "-d", str(exe)], text=True)
        if elf_type not in elf or any(tag in elf for tag in ("INTERP", "NEEDED", "TEXTREL")):
            raise ValueError("Unexpected static executable format")
    run([str(work / "unwind-probe")], timeout=20)
    return True


def build(target: str, directory: Path, jobs: int) -> Path:
    recipe = json.loads(RECIPE.read_bytes())
    zig = windows_runtime.resolve_zig()
    if subprocess.check_output([zig, "version"], text=True).strip() != recipe["zig_version"]:
        raise ValueError("Producer Zig version differs from recipe")
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="basic-cli-linker-") as temporary:
        work = Path(temporary)
        output = work / "output"
        output.mkdir()
        if target == "x64win":
            windows_runtime.build(output, zig=zig)
        else:
            build_linux(target, output, work, zig, recipe, jobs)
        native_validation = validate_native(target, output, work, zig, recipe)
        manifest = {
            "format_version": 1, "target": target, "recipe": recipe,
            "native_validation": native_validation,
            "sources": {p.relative_to(ROOT).as_posix(): sha256(p)
                        for p in sorted((ROOT / "native").rglob("*")) if p.is_file()},
            "producer_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "producer_sha256": sha256(Path(__file__)),
            "startup_modification": "Treat an absent dynamic section as empty for fixed-address static executables.",
            "files": {p.relative_to(output).as_posix(): {"sha256": sha256(p), "size": p.stat().st_size}
                      for p in sorted(output.rglob("*")) if p.is_file()},
        }
        (output / "LINKER_INPUTS.json").write_bytes(canonical(manifest))
        verify(output, target)
        archive = work / "inputs.tar.gz"
        with archive.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as packed:
                for path in sorted(output.rglob("*")):
                    if path.is_file():
                        data = path.read_bytes()
                        entry = tarfile.TarInfo(path.relative_to(output).as_posix())
                        entry.mode = 0o644
                        entry.size = len(data)
                        packed.addfile(entry, io.BytesIO(data))
        result = directory / f"{target}-{sha256(archive)}.tar.gz"
        shutil.copyfile(archive, result)
    print(result)
    return result


def release_manifest(directory: Path, repository: str) -> None:
    targets = {}
    for target in INVENTORY:
        archives = list(directory.glob(f"{target}-*.tar.gz"))
        if len(archives) != 1:
            raise ValueError(f"Expected one {target} archive")
        archive = archives[0]
        with tempfile.TemporaryDirectory() as temporary:
            unpack(archive, Path(temporary))
            manifest = verify(Path(temporary), target)
            if not manifest.get("native_validation"):
                raise ValueError(f"{target} has not passed native validation")
        targets[target] = {"asset": archive.name, "sha256": sha256(archive), "size": archive.stat().st_size}
    identity = hashlib.sha256(canonical(targets)).hexdigest()
    tag = "linker-inputs-" + identity
    lock = {"format_version": 1, "release": tag, "targets": {
        target: {**record, "url": f"https://github.com/{repository}/releases/download/{tag}/{record['asset']}"}
        for target, record in targets.items()}}
    (directory / "linker-inputs.lock.json").write_bytes(canonical(lock))
    print(tag)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("build", "fetch", "check", "manifest"))
    parser.add_argument("--target", choices=INVENTORY)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--repository", default="roc-lang/basic-cli")
    parser.add_argument("--lock", type=Path, default=LOCK)
    args = parser.parse_args()
    if args.operation == "manifest":
        release_manifest(args.directory, args.repository)
    elif args.target is None:
        parser.error("--target is required")
    elif args.operation == "build":
        if args.jobs < 1:
            parser.error("--jobs must be positive")
        build(args.target, args.directory.resolve(), args.jobs)
    elif args.operation == "fetch":
        restore(args.target, args.directory, lock=args.lock)
    else:
        verify(args.directory, args.target)


if __name__ == "__main__":
    main()
