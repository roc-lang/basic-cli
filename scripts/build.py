#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path

try:
    from . import windows_runtime
except ImportError:
    import windows_runtime


ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "x64mac": "x86_64-apple-darwin",
    "arm64mac": "aarch64-apple-darwin",
    "x64musl": "x86_64-unknown-linux-musl",
    "arm64musl": "aarch64-unknown-linux-musl",
}
ALL_TARGETS = tuple(TARGETS)
ROC_TARGETS = (*ALL_TARGETS, "x64win")
WINDOWS_TARGET = "x86_64-pc-windows-msvc"


def run(*args: str, env: dict[str, str] | None = None, check: bool = True) -> None:
    subprocess.run(args, cwd=ROOT, env=env, check=check)


def rust_host_target() -> str:
    output = subprocess.check_output(["rustc", "-vV"], text=True)
    for line in output.splitlines():
        if line.startswith("host: "):
            return line.removeprefix("host: ")
    raise SystemExit("Could not determine the Rust host target")


def find_llvm_strip() -> Path:
    executable = shutil.which("llvm-strip")
    if executable:
        return Path(executable)

    sysroot = Path(subprocess.check_output(["rustc", "--print", "sysroot"], text=True).strip())
    suffix = ".exe" if platform.system() == "Windows" else ""
    executable = sysroot / "lib" / "rustlib" / rust_host_target() / "bin" / ("llvm-strip" + suffix)
    if executable.is_file():
        return executable

    raise SystemExit(
        "llvm-strip was not found; install it with "
        "`rustup component add llvm-tools-preview`"
    )


def strip_linux_host(target_name: str) -> None:
    if not target_name.endswith("musl"):
        return

    path = ROOT / "platform" / "targets" / target_name / "libhost.a"
    before = path.stat().st_size
    # ELF's strip-unneeded mode retains every symbol referenced by a
    # relocation while dropping debug data and unused symbols.
    run(str(find_llvm_strip()), "--strip-unneeded", str(path))
    after = path.stat().st_size
    print(f"Stripped {target_name} libhost.a: {before} -> {after} bytes")


def detect_native_target() -> str:
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Windows" and machine in {"amd64", "x86_64"}:
        return "x64win"
    if system == "Darwin":
        if machine in {"arm64", "aarch64"}:
            return "arm64mac"
        if machine in {"x86_64", "amd64"}:
            return "x64mac"
    if system == "Linux":
        if machine in {"aarch64", "arm64"}:
            return "arm64musl"
        if machine in {"x86_64", "amd64"}:
            return "x64musl"

    raise SystemExit(f"Unsupported native platform: {system} {machine}")


def musl_build_env(rust_target: str) -> dict[str, str]:
    env = os.environ.copy()
    zig_targets = {
        "x86_64-unknown-linux-musl": "x86_64-linux-musl",
        "aarch64-unknown-linux-musl": "aarch64-linux-musl",
    }
    zig_target = zig_targets.get(rust_target)
    if zig_target is None or shutil.which("zig") is None:
        return env

    key = rust_target.replace("-", "_")
    env["ZIG_CC_TARGET"] = zig_target
    env[f"CC_{key}"] = str(ROOT / "ci" / "zig-cc.sh")
    env[f"AR_{key}"] = str(ROOT / "ci" / "zig-ar.sh")
    env[f"CFLAGS_{key}"] = "-Wno-error"
    print(f"  (using zig cc for {rust_target})")
    return env


def rust_target_is_installed(rust_target: str) -> bool:
    result = subprocess.run(
        ["rustc", "--print", "target-libdir", "--target", rust_target],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return result.returncode == 0 and Path(result.stdout.strip()).is_dir()


def install_rust_target(rust_target: str, *, required: bool = False) -> None:
    if rust_target_is_installed(rust_target):
        return

    if shutil.which("rustup") is None:
        message = (
            f"Rust target {rust_target} is not installed and rustup is unavailable; "
            "enter `nix develop` or install the target manually"
        )
        if required:
            raise SystemExit(message)
        print(f"warning: {message}")
        return

    run("rustup", "target", "add", rust_target, check=required)


def copy_unix_host(target_name: str, rust_target: str, *, native: bool) -> None:
    output_dir = ROOT / "platform" / "targets" / target_name
    output_dir.mkdir(parents=True, exist_ok=True)
    source = ROOT / "target" / rust_target / "release" / "libhost.a"

    if native and target_name in {"x64mac", "arm64mac"}:
        run("cargo", "build", "--locked", "--release", "--lib")
        source = ROOT / "target" / "release" / "libhost.a"
    else:
        run(
            "cargo",
            "build",
            "--locked",
            "--release",
            "--lib",
            "--target",
            rust_target,
            env=musl_build_env(rust_target),
        )

    destination = output_dir / "libhost.a"
    shutil.copy2(source, destination)
    print(f"  -> {destination.relative_to(ROOT)}")


def build_unix_target(target_name: str, *, native: bool = False) -> None:
    rust_target = TARGETS[target_name]
    qualifier = "native" if native else rust_target
    print(f"Building for {target_name} ({qualifier})...")
    copy_unix_host(target_name, rust_target, native=native)
    strip_linux_host(target_name)


def windows_build_env() -> tuple[dict[str, str], str]:
    compiler = shutil.which("clang-cl")
    if compiler is None:
        raise SystemExit("clang-cl was not found; install LLVM and add its bin directory to PATH")
    env = os.environ.copy()
    env["CC_x86_64_pc_windows_msvc"] = compiler
    # System UCRT import inputs match the standard dynamic CRT configuration.
    # Preserve other flags, but ensure an inherited +crt-static does not bundle
    # Microsoft CRT archives into host.lib.
    existing = env.get("CARGO_ENCODED_RUSTFLAGS")
    if existing is None:
        existing = "\x1f".join(env.get("RUSTFLAGS", "").split())
    env["CARGO_ENCODED_RUSTFLAGS"] = existing + ("\x1f" if existing else "") + "-Ctarget-feature=-crt-static"
    return env, compiler


def build_windows() -> None:
    print(f"Building for x64win ({WINDOWS_TARGET})...")
    install_rust_target(WINDOWS_TARGET, required=True)
    env, compiler = windows_build_env()
    build_command = ["cargo", "build", "--locked", "--release", "--lib", "--target", WINDOWS_TARGET]
    run(*build_command, env=env)

    output_dir = ROOT / "platform" / "targets" / "x64win"
    windows_runtime.build(output_dir)
    host_destination = output_dir / "host.lib"
    shutil.copy2(
        ROOT / "target" / WINDOWS_TARGET / "release" / "host.lib",
        host_destination,
    )
    print(f"  -> {host_destination.relative_to(ROOT)}")

    windows_runtime.record_host(output_dir, [build_command], {
        "c_compiler": subprocess.check_output([compiler, "--version"], text=True).strip(),
        "rust_flags": env["CARGO_ENCODED_RUSTFLAGS"],
        "c_compiler_env": "CC_x86_64_pc_windows_msvc=" + compiler,
    })


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the basic-cli platform host")
    parser.add_argument(
        "--all",
        action="store_true",
        help="cross-compile all macOS and Linux targets",
    )
    parser.add_argument(
        "--target",
        choices=ROC_TARGETS,
        help="build host inputs for one Roc platform target",
    )
    args = parser.parse_args()

    if args.all and args.target:
        parser.error("--all and --target are mutually exclusive")

    if args.target:
        if args.target == "x64win":
            if platform.system() != "Windows":
                parser.error("x64win host inputs must be built on Windows")
            build_windows()
        else:
            install_rust_target(TARGETS[args.target], required=True)
            build_unix_target(args.target, native=args.target == detect_native_target())
        print("\nBuild complete!")
        return

    if args.all:
        if platform.system() == "Windows":
            parser.error("--all requires a macOS or Linux host")
        print("Building for all targets...\n")
        for target_name in ALL_TARGETS:
            install_rust_target(TARGETS[target_name])
        print()
        for target_name in ALL_TARGETS:
            build_unix_target(target_name)
            print()
        print("All targets built successfully!")
        return

    target_name = detect_native_target()
    print(f"Building for native target: {target_name}\n")
    if target_name == "x64win":
        build_windows()
    else:
        if target_name in {"x64musl", "arm64musl"}:
            install_rust_target(TARGETS[target_name])
        build_unix_target(target_name, native=True)
    print("\nBuild complete!")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
