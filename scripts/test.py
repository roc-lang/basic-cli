#!/usr/bin/env python3
from __future__ import annotations

import argparse
import atexit
import contextlib
import functools
import hashlib
import json
import os
import platform
import re
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator

from build import ROC_TARGETS, detect_native_target
from update_app_platform_urls import update_apps

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")

ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "scripts" / "test_spec.json"
STAGES = ("fmt", "check", "test", "build", "run")
APP_DIRS = (ROOT / "examples", ROOT / "tests", ROOT / "tests" / "resource-lifetimes")
DEFAULT_ARTIFACT_DIR = ROOT / "dist" / "example-binaries"
ROC = os.environ.get("ROC", "roc")
# A case with "live_handles": N sets this, making the host report at exit how
# many native resource handles are still open, and requires the total to be N.
LIVE_HANDLES_ENV = "BASIC_CLI_LIVE_HANDLES"
VALGRIND_ARGS = (
    "valgrind",
    "--error-exitcode=99",
    "--leak-check=full",
    "--show-leak-kinds=all",
    "--errors-for-leak-kinds=all",
    "--track-origins=yes",
    "--realloc-zero-bytes-frees=no",
    f"--suppressions={ROOT / 'ci' / 'valgrind.supp'}",
)


def declared_targets() -> tuple[str, ...]:
    lines = (ROOT / "platform" / "main.roc").read_text(encoding="utf-8").splitlines()
    in_targets = False
    targets: list[str] = []
    for line in lines:
        if not in_targets:
            if re.match(r"^\s*targets:\s*\{\s*$", line):
                in_targets = True
            continue
        if re.match(r"^\s*}\s*$", line) and not line.startswith("\t\t"):
            break
        match = re.match(r"^\s{2,}([A-Za-z0-9_]+):\s*\{\s*inputs:", line.expandtabs(4))
        if match:
            targets.append(match.group(1))
    if not targets:
        raise SystemExit("platform/main.roc: no platform targets found")
    unknown = sorted(set(targets) - set(ROC_TARGETS))
    missing = sorted(set(ROC_TARGETS) - set(targets))
    if unknown or missing:
        raise SystemExit(f"Platform/build target mismatch; unknown={unknown}, missing={missing}")
    return tuple(targets)


def command(*args: str | Path, cwd: Path = ROOT) -> None:
    values = [str(arg) for arg in args]
    print(f"+ {' '.join(values)}", flush=True)
    subprocess.run(values, cwd=cwd, check=True)


def binary_stem(source: Path) -> str:
    """Name an app's binary; apps in nested directories are prefixed to stay unique."""
    parts = source.relative_to(ROOT).with_suffix("").parts
    return "-".join(parts[1:])


def roc_extra_args() -> tuple[str, ...]:
    args = ("--max-transitive-mb=256",)
    return (*args, "--no-cache") if platform.system() == "Windows" else args


def load_spec() -> tuple[dict[str, bool], list[dict[str, object]]]:
    data = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    defaults = data.get("stages")
    apps = data.get("apps")
    if not isinstance(defaults, dict) or set(defaults) != set(STAGES):
        raise SystemExit(f"{SPEC_PATH}: 'stages' must define {', '.join(STAGES)}")
    if not all(isinstance(defaults[name], bool) for name in STAGES):
        raise SystemExit(f"{SPEC_PATH}: all stage flags must be booleans")
    if not isinstance(apps, list) or not all(isinstance(app, dict) for app in apps):
        raise SystemExit(f"{SPEC_PATH}: 'apps' must be a list of objects")

    paths = [app.get("path") for app in apps]
    if not all(isinstance(path, str) for path in paths) or len(paths) != len(set(paths)):
        raise SystemExit(f"{SPEC_PATH}: every app needs a unique string path")
    discovered = {
        str(path.relative_to(ROOT).as_posix())
        for directory in APP_DIRS
        for path in directory.glob("*.roc")
    }
    specified = set(paths)
    if discovered != specified:
        missing = sorted(discovered - specified)
        extra = sorted(specified - discovered)
        raise SystemExit(f"Test spec mismatch; missing={missing}, extra={extra}")
    for app in apps:
        if "run" in app:
            raise SystemExit(f"{app['path']}: use the cases array; singular run is not supported")
        cases = run_cases(app)
        if stage_enabled(defaults, app, "run") and not cases:
            raise SystemExit(f"{app['path']}: run is enabled but cases is empty")
    return defaults, apps


def stage_enabled(defaults: dict[str, bool], app: dict[str, object], stage: str) -> bool:
    app_enabled = app.get("enabled", True)
    if not isinstance(app_enabled, bool):
        raise SystemExit(f"{app['path']}: enabled flag must be a boolean")
    enabled = defaults[stage]
    overrides = app.get("stages", {})
    if isinstance(overrides, dict) and stage in overrides:
        enabled = overrides[stage]
    system = platform.system().lower()
    platforms = app.get("platforms", {})
    if isinstance(platforms, dict):
        platform_overrides = platforms.get(system, {})
        if isinstance(platform_overrides, dict):
            platform_enabled = platform_overrides.get("enabled", True)
            if not isinstance(platform_enabled, bool):
                raise SystemExit(f"{app['path']}: platform enabled flag must be a boolean")
            app_enabled = app_enabled and platform_enabled
            if stage in platform_overrides:
                enabled = platform_overrides[stage]
    if not isinstance(enabled, bool):
        raise SystemExit(f"{app['path']}: {stage} flag must be a boolean")
    return app_enabled and enabled


def create_bundle() -> Path:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "bundle.py"), "--stub-missing-targets"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    result.check_returncode()
    matches = re.findall(r"^Created:\s+(.+\.tar\.zst)\s*$", result.stdout, re.MULTILINE)
    if not matches:
        raise SystemExit("Bundle creation did not report a created archive")
    bundle = Path(matches[-1])
    if not bundle.is_absolute():
        bundle = ROOT / bundle
    if not bundle.is_file():
        raise SystemExit(f"Bundle creation did not produce an archive: {bundle}")
    return bundle.resolve()


class BundleServer:
    def __init__(self, bundle: Path) -> None:
        handler = functools.partial(SimpleHTTPRequestHandler, directory=str(bundle.parent))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.url = f"http://127.0.0.1:{self.server.server_port}/{bundle.name}"

    def __enter__(self) -> str:
        self.thread.start()
        with urllib.request.urlopen(
            urllib.request.Request(self.url, method="HEAD"), timeout=5
        ):
            pass
        return self.url

    def __exit__(self, *_: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()


def expand(value: str, source: Path) -> str:
    return value.format(root=ROOT, source=source, source_dir=source.parent, python=sys.executable)


def wait_for_port(port: int, process: subprocess.Popen[bytes], timeout: float = 5) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"Helper server on port {port} exited early")
        with socket.socket() as sock:
            sock.settimeout(0.1)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.05)
    raise SystemExit(f"Helper server did not listen on port {port}")


@contextlib.contextmanager
def helper_server(name: str | None) -> Iterator[None]:
    if name is None:
        yield
        return
    if name == "http":
        suffix = ".exe" if platform.system() == "Windows" else ""
        args = [str(ROOT / "ci" / "rust_http_server" / "target" / "release" / f"rust_http_server{suffix}")]
        port = 9000
    elif name == "tcp":
        args = [sys.executable, str(ROOT / "scripts" / "tcp_echo_server.py")]
        port = 8085
    else:
        raise SystemExit(f"Unknown helper server: {name}")
    process = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        wait_for_port(port, process)
        yield
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def pipe_process(
    args: list[str], cwd: Path, env: dict[str, str] | dict[bytes, bytes],
    stdin: bytes, timeout: float, *, detach_terminal: bool = False,
) -> tuple[int, str, str]:
    detach: dict[str, object] = {}
    if detach_terminal:
        # A process can reach its terminal without using the standard streams,
        # so leave it with no controlling terminal or console at all.
        if os.name == "posix":
            detach["start_new_session"] = True
        else:
            detach["creationflags"] = subprocess.DETACHED_PROCESS
    result = subprocess.run(
        args, cwd=cwd, env=env, input=stdin, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, **detach,
    )
    return (
        result.returncode,
        result.stdout.decode("utf-8", errors="replace"),
        result.stderr.decode("utf-8", errors="replace"),
    )


def pty_process(
    args: list[str], cwd: Path, env: dict[str, str], stdin: bytes, timeout: float,
    input_delay: float, *, await_raw_mode: bool = False, send_signal: str | None = None,
) -> tuple[int, str]:
    import pty
    import termios

    def terminal_mode() -> list[object]:
        mode = termios.tcgetattr(slave)
        # BSD kernels set PENDIN themselves when a terminal returns to line mode,
        # and only clear it on the next read. It is not part of the requested mode.
        mode[3] &= ~getattr(termios, "PENDIN", 0)
        return mode

    master, slave = pty.openpty()
    # The slave stays open so the terminal mode can be read after the child exits.
    initial_mode = terminal_mode()
    process = subprocess.Popen(args, cwd=cwd, env=env, stdin=slave, stdout=slave, stderr=slave)
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        if await_raw_mode:
            while terminal_mode() == initial_mode:
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise SystemExit(f"Terminal never changed mode: {' '.join(args)}")
                time.sleep(0.01)
        else:
            time.sleep(0.25)
        for byte in stdin:
            os.write(master, bytes([byte]))
            time.sleep(input_delay)
        if send_signal is not None:
            process.send_signal(getattr(signal, send_signal))
        while process.poll() is None:
            if time.monotonic() >= deadline:
                process.kill()
                raise SystemExit(f"Timed out after {timeout}s: {' '.join(args)}")
            readable, _, _ = select.select([master], [], [], 0.1)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                    if not chunk:
                        break
                    output.extend(chunk)
                except OSError:
                    break
        while True:
            readable, _, _ = select.select([master], [], [], 0)
            if not readable:
                break
            try:
                chunk = os.read(master, 65536)
                if not chunk:
                    break
                output.extend(chunk)
            except OSError:
                break
        exit_code = process.wait()
        final_mode = terminal_mode()
        if final_mode != initial_mode:
            raise SystemExit(
                f"Terminal mode was not restored: {' '.join(args)}"
                f"\n  before: {initial_mode}\n  after:  {final_mode}"
            )
        return exit_code, output.decode("utf-8", errors="replace")
    finally:
        os.close(slave)
        os.close(master)
        if process.poll() is None:
            process.kill()
            process.wait()


def console_process(
    args: list[str], cwd: Path, env: dict[str, str], stdin: bytes, timeout: float,
    input_delay: float, *, await_raw_mode: bool = False, send_signal: str | None = None,
) -> tuple[int, str]:
    """Windows counterpart of pty_process; see scripts/windows_console.py."""
    request = {
        "args": args, "stdin": stdin.decode(), "timeout": timeout, "input_delay": input_delay,
        "await_raw_mode": await_raw_mode, "send_signal": send_signal,
    }
    hidden = subprocess.STARTUPINFO()
    hidden.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    hidden.wShowWindow = subprocess.SW_HIDE
    runner = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "windows_console.py"), json.dumps(request)],
        cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=timeout + 10,
        creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=hidden,
    )
    if runner.returncode != 0 or not runner.stdout.strip():
        raise SystemExit(f"Console runner failed: {' '.join(args)}\n{runner.stderr}")
    result = json.loads(runner.stdout)
    if "error" in result:
        raise SystemExit(f"{result['error']}: {' '.join(args)}")
    return int(result["exit_code"]), str(result["output"])


def signal_exit_code(name: str) -> int:
    # Windows has no signals; the console runner sends Ctrl+Break in their place.
    if os.name != "posix":
        return 0xC000013A  # STATUS_CONTROL_C_EXIT
    return -int(getattr(signal, name))


def make_environment(run_spec: dict[str, object], source: Path) -> dict[str, str] | dict[bytes, bytes]:
    env = os.environ.copy()
    for name in run_spec.get("unset_env", []):
        env.pop(str(name), None)
    values = run_spec.get("env", {})
    if not isinstance(values, dict):
        raise SystemExit(f"{source}: run.env must be an object")
    for name, value in values.items():
        env[str(name)] = expand(str(value), source)
    if "live_handles" in run_spec:
        env[LIVE_HANDLES_ENV] = "1"
    non_utf8 = run_spec.get("non_utf8_env", {})
    if non_utf8 and os.name == "posix":
        byte_env = {name.encode(): value.encode() for name, value in env.items()}
        for name, value in non_utf8.items():
            byte_env[str(name).encode()] = bytes.fromhex(str(value))
        return byte_env
    return env


def verify_text(source: Path, case_name: str, stream: str, output: str,
                contains: object, regexes: object, *, expect_crash: bool = False) -> None:
    normalized = output.replace("\r\n", "\n").replace("\r", "\n")
    if "[ROC CRASHED]" in normalized and not expect_crash:
        raise SystemExit(f"{source}: runtime crash\n{normalized}")
    if not isinstance(contains, list) or not isinstance(regexes, list):
        raise SystemExit(f"{source} [{case_name}]: {stream} assertions must be arrays")
    for expected in contains:
        if str(expected) not in normalized:
            raise SystemExit(
                f"{source} [{case_name}]: missing {stream} output {expected!r}"
                f"\n--- {stream} ---\n{normalized}"
            )
    for pattern in regexes:
        if re.search(str(pattern), normalized, re.MULTILINE) is None:
            raise SystemExit(
                f"{source} [{case_name}]: {stream} did not match {pattern!r}"
                f"\n--- {stream} ---\n{normalized}"
            )


def verify_output(source: Path, case_name: str, stdout: str, stderr: str,
                  run_spec: dict[str, object], *, pty: bool) -> None:
    combined = stdout if pty else stdout + stderr
    expect_crash = bool(run_spec.get("expect_crash"))
    verify_text(source, case_name, "combined output", combined,
                run_spec.get("contains", []), run_spec.get("regex", []),
                expect_crash=expect_crash)
    if pty and any(name in run_spec for name in (
        "stdout_contains", "stdout_regex", "stderr_contains", "stderr_regex"
    )):
        raise SystemExit(f"{source} [{case_name}]: PTY cases cannot assert separate streams")
    if "live_handles" in run_spec:
        expected = run_spec["live_handles"]
        if isinstance(expected, bool) or not isinstance(expected, int):
            raise SystemExit(f"{source} [{case_name}]: live_handles must be an integer")
        # The host writes the report to stderr, which a PTY merges into stdout.
        # Child processes inherit the variable and may report too, so every
        # report must match: one child's zero must not hide the app's leak.
        reports = re.findall(r"^live handles: (\d+)\r?$", stdout if pty else stderr, re.MULTILINE)
        if not reports or any(int(count) != expected for count in reports):
            raise SystemExit(
                f"{source} [{case_name}]: expected every live-handle report to be "
                f"{expected}, got {reports or 'none'}"
            )
    if not pty:
        verify_text(source, case_name, "stdout", stdout,
                    run_spec.get("stdout_contains", []), run_spec.get("stdout_regex", []),
                    expect_crash=expect_crash)
        verify_text(source, case_name, "stderr", stderr,
                    run_spec.get("stderr_contains", []), run_spec.get("stderr_regex", []),
                    expect_crash=expect_crash)


def run_cases(app: dict[str, object]) -> list[dict[str, object]]:
    cases = app.get("cases", [])
    if not isinstance(cases, list) or not all(isinstance(case, dict) for case in cases):
        raise SystemExit(f"{app['path']}: cases must be a list of objects")
    names = [case.get("name") for case in cases]
    if not all(isinstance(name, str) and name for name in names) or len(names) != len(set(names)):
        raise SystemExit(f"{app['path']}: every run case needs a unique non-empty name")
    return cases


def case_enabled(case: dict[str, object]) -> bool:
    enabled = case.get("enabled", True)
    if not isinstance(enabled, bool):
        raise SystemExit(f"Run case {case.get('name')}: enabled must be a boolean")
    platforms = case.get("platforms", {})
    if isinstance(platforms, dict):
        override = platforms.get(platform.system().lower(), {})
        if isinstance(override, dict):
            platform_enabled = override.get("enabled", True)
            if not isinstance(platform_enabled, bool):
                raise SystemExit(f"Run case {case.get('name')}: platform enabled must be boolean")
            enabled = enabled and platform_enabled
    return enabled


def merged_rw_segment_patches(image: bytes) -> list[tuple[int, int]]:
    """Find the `p_filesz` fields Valgrind needs widened to load an ELF's symbols.

    Valgrind reads a binary's symbol table only once it has seen as many
    writable mappings as it expects. Two writable PT_LOAD segments that are
    adjacent in memory get mapped as one, and Valgrind allows for that only when
    the first one's file size reaches the second (`p_vaddr + p_filesz`). lld
    ends the first with `.relro_padding`, which occupies memory but not the
    file, so Valgrind waits for a mapping that never comes, reports every frame
    as `???`, and no `fun:` suppression can match.

    The padding is zero-filled in memory and the bytes that follow the segment
    in the file are zero too, so extending the file size over them loads the
    same image. Returns (offset, value) pairs to write as little-endian u64.
    """
    if image[:6] != b"\x7fELF\x02\x01":
        return []
    program_headers, = struct.unpack_from("<Q", image, 32)
    entry_size, entry_count = struct.unpack_from("<HH", image, 54)
    patches: list[tuple[int, int]] = []
    previous: tuple[int, int, int, int, int] | None = None
    for index in range(entry_count):
        entry = program_headers + index * entry_size
        kind, flags, offset, address, _, file_size, memory_size, _ = struct.unpack_from("<IIQQQQQQ", image, entry)
        # PT_LOAD, readable and writable but not executable.
        if kind != 1 or flags & 7 != 6 or memory_size == 0:
            continue
        if previous is not None:
            previous_entry, previous_offset, previous_address, previous_file_size, previous_memory_size = previous
            padded = previous_file_size < previous_memory_size
            adjacent = previous_address + previous_memory_size == address
            in_file = previous_offset + previous_memory_size <= offset
            padding = image[previous_offset + previous_file_size:previous_offset + previous_memory_size]
            if padded and adjacent and in_file and not any(padding):
                patches.append((previous_entry + 32, previous_memory_size))
        previous = (entry, offset, address, file_size, memory_size)
    return patches


@functools.cache
def valgrind_scratch_dir() -> Path:
    directory = Path(tempfile.mkdtemp(prefix="basic-cli-valgrind-"))
    atexit.register(shutil.rmtree, directory, ignore_errors=True)
    return directory


@functools.cache
def valgrind_binary(binary: Path) -> Path:
    """Return a binary Valgrind can read symbols from: `binary`, or a patched copy."""
    image = bytearray(binary.read_bytes())
    patches = merged_rw_segment_patches(bytes(image))
    if not patches:
        return binary
    for offset, value in patches:
        struct.pack_into("<Q", image, offset, value)
    digest = hashlib.sha256(str(binary).encode()).hexdigest()[:16]
    copy = valgrind_scratch_dir() / digest / binary.name
    copy.parent.mkdir()
    copy.write_bytes(image)
    shutil.copymode(binary, copy)
    return copy


def run_binary(
    app: dict[str, object], binary: Path, run_spec: dict[str, object], *,
    valgrind: bool,
) -> None:
    source = ROOT / str(app["path"])
    case_name = str(run_spec["name"])
    print(f"\n--- {app['path']} [{case_name}] ---")
    if valgrind:
        binary = valgrind_binary(binary)
    args = [str(binary), *(expand(str(value), source) for value in run_spec.get("args", []))]
    if valgrind:
        args = [*VALGRIND_ARGS, *args]
    temporary_cwd = tempfile.TemporaryDirectory(prefix="basic-cli-case-") if run_spec.get("temp_cwd") else None
    cwd = Path(temporary_cwd.name) if temporary_cwd else Path(expand(str(run_spec.get("cwd", "{root}")), source))
    if "stdin_hex" in run_spec:
        stdin = bytes.fromhex(str(run_spec["stdin_hex"]))
    else:
        stdin = str(run_spec.get("stdin", "")).encode()
    timeout = float(run_spec.get("timeout", 7)) * (4 if valgrind else 1)
    send_signal = run_spec.get("send_signal")
    if send_signal is not None and not (isinstance(send_signal, str) and run_spec.get("pty")):
        raise SystemExit(f"{source} [{case_name}]: send_signal needs a signal name and a PTY case")
    fixtures = run_spec.get("fixtures", [])
    fixture_targets: list[Path] = []
    for fixture in fixtures:
        target = ROOT / str(fixture["target"])
        shutil.copy2(ROOT / str(fixture["source"]), target)
        fixture_targets.append(target)
    try:
        with helper_server(run_spec.get("helper")):
            env = make_environment(run_spec, source)
            if run_spec.get("pty"):
                if not isinstance(env, dict) or any(isinstance(key, bytes) for key in env):
                    raise SystemExit(f"{source}: PTY tests require a text environment")
                terminal_process = pty_process if os.name == "posix" else console_process
                exit_code, stdout = terminal_process(
                    args, cwd, env, stdin, timeout,
                    float(run_spec.get("input_delay", 0.08)),
                    await_raw_mode=bool(run_spec.get("await_raw_mode")),
                    send_signal=send_signal,
                )
                stderr = ""
            else:
                exit_code, stdout, stderr = pipe_process(
                    args, cwd, env, stdin, timeout,
                    detach_terminal=bool(run_spec.get("detach_terminal")),
                )
        if stdout:
            print(stdout, end="" if stdout.endswith("\n") else "\n")
        if stderr:
            print(stderr, end="" if stderr.endswith("\n") else "\n", file=sys.stderr)
        expected_exit = int(run_spec.get(
            "exit_code", 0 if send_signal is None else signal_exit_code(send_signal)
        ))
        if exit_code != expected_exit:
            raise SystemExit(f"{source} [{case_name}]: exited with {exit_code}, expected {expected_exit}")
        verify_output(source, case_name, stdout, stderr, run_spec, pty=bool(run_spec.get("pty")))
    finally:
        for target in fixture_targets:
            target.unlink(missing_ok=True)
        if temporary_cwd is not None:
            temporary_cwd.cleanup()


def run_stage(
    stage: str, defaults: dict[str, bool], apps: list[dict[str, object]],
    binaries: dict[str, Path], build_dir: Path, target: str, *, valgrind: bool = False,
) -> None:
    print(f"\n=== {stage.upper()} ===")
    for app in apps:
        path = str(app["path"])
        source = ROOT / path
        if not stage_enabled(defaults, app, stage):
            reason = f" ({app['reason']})" if app.get("reason") else ""
            print(f"SKIP {stage}: {path}{reason}")
            continue
        if stage == "fmt":
            command(ROC, "fmt", "--check", source)
        elif stage == "check":
            command(ROC, "check", source, *roc_extra_args())
        elif stage == "test":
            command(ROC, "test", source, *roc_extra_args())
        elif stage == "build":
            suffix = ".exe" if target == "x64win" else ""
            binary = build_dir / target / f"{binary_stem(source)}{suffix}"
            binary.parent.mkdir(parents=True, exist_ok=True)
            command(
                ROC, "build", source, f"--target={target}",
                f"--output={binary}", *roc_extra_args(),
            )
            binaries[path] = binary
        elif stage == "run":
            binary = binaries.get(path)
            if binary is None:
                raise SystemExit(f"{path}: run is enabled but build is disabled")
            for run_spec in run_cases(app):
                if valgrind and run_spec.get("valgrind") is False:
                    print(f"SKIP run case under Valgrind: {path} [{run_spec['name']}]")
                elif case_enabled(run_spec):
                    run_binary(app, binary, run_spec, valgrind=valgrind)
                else:
                    print(f"SKIP run case: {path} [{run_spec['name']}]")


def spec_hash() -> str:
    return hashlib.sha256(SPEC_PATH.read_bytes()).hexdigest()


def sources_hash(paths: object, contents: dict[Path, bytes] | None = None) -> str:
    if not isinstance(paths, (set, list, tuple, dict)):
        raise SystemExit("Cannot hash artifact sources")
    names = paths.keys() if isinstance(paths, dict) else paths
    digest = hashlib.sha256()
    for name in sorted(str(value) for value in names):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        path = ROOT / name
        digest.update(contents[path] if contents is not None else path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def write_manifest(target: str, binaries: dict[str, Path], artifact_dir: Path,
                   source_sha256: str) -> None:
    manifest = {
        "target": target,
        "spec_sha256": spec_hash(),
        "sources_sha256": source_sha256,
        "binaries": {
            source: str(binary.relative_to(artifact_dir).as_posix())
            for source, binary in sorted(binaries.items())
        },
    }
    path = artifact_dir / target / "manifest.json"
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def load_artifact_binaries(target: str, artifact_dir: Path,
                           defaults: dict[str, bool], apps: list[dict[str, object]]) -> dict[str, Path]:
    manifest_path = artifact_dir / target / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit(f"Missing artifact manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("target") != target:
        raise SystemExit(f"{manifest_path}: target does not match {target}")
    if manifest.get("spec_sha256") != spec_hash():
        raise SystemExit(f"{manifest_path}: artifacts were built from a different test spec")
    entries = manifest.get("binaries")
    if not isinstance(entries, dict):
        raise SystemExit(f"{manifest_path}: binaries must be an object")
    expected = {
        str(app["path"]) for app in apps if stage_enabled(defaults, app, "build")
    }
    if manifest.get("sources_sha256") != sources_hash(expected):
        raise SystemExit(f"{manifest_path}: artifacts were built from different example sources")
    if set(entries) != expected:
        raise SystemExit(
            f"{manifest_path}: binary mismatch; missing={sorted(expected - set(entries))}, "
            f"extra={sorted(set(entries) - expected)}"
        )
    binaries = {source: artifact_dir / str(relative) for source, relative in entries.items()}
    missing = sorted(source for source, binary in binaries.items() if not binary.is_file())
    if missing:
        raise SystemExit(f"{manifest_path}: missing binary files for {missing}")
    if os.name == "posix":
        for binary in binaries.values():
            binary.chmod(binary.stat().st_mode | 0o111)
    return binaries


def run_artifact_cases(target: str, artifact_dir: Path, *, valgrind: bool) -> None:
    defaults, apps = load_spec()
    binaries = load_artifact_binaries(target, artifact_dir, defaults, apps)
    if any(
        stage_enabled(defaults, app, "run")
        and any(case_enabled(case) and case.get("helper") == "http" for case in run_cases(app))
        for app in apps
    ):
        command("cargo", "build", "--locked", "--release", cwd=ROOT / "ci" / "rust_http_server")
    run_stage("run", defaults, apps, binaries, artifact_dir, target, valgrind=valgrind)


def run_suite(
    bundle_url: str, operations: set[str], target: str, artifact_dir: Path, *,
    valgrind: bool,
) -> None:
    defaults, apps = load_spec()
    sources = [ROOT / str(app["path"]) for app in apps]
    backups = {path: path.read_bytes() for path in sources}
    original_sources_sha256 = sources_hash(
        [str(path.relative_to(ROOT).as_posix()) for path in sources], backups
    )
    try:
        update_apps(list(APP_DIRS), bundle_url)
        if "run" in operations and any(
            stage_enabled(defaults, app, "run")
            and any(case_enabled(case) and case.get("helper") == "http" for case in run_cases(app))
            for app in apps
        ):
            command("cargo", "build", "--locked", "--release", cwd=ROOT / "ci" / "rust_http_server")
        binaries: dict[str, Path] = {}
        if "validate" in operations:
            print("\n=== RUST TEST ===")
            command("cargo", "test", "--locked", "--lib")
            print("\n=== PLATFORM TEST ===")
            command(ROC, "test", ROOT / "platform" / "main.roc", *roc_extra_args())
        for stage in ("fmt", "check", "test"):
            if "validate" in operations:
                run_stage(stage, defaults, apps, binaries, artifact_dir, target)
        if "build" in operations:
            run_stage("build", defaults, apps, binaries, artifact_dir, target)
            write_manifest(target, binaries, artifact_dir, original_sources_sha256)
        if "run" in operations:
            if not binaries:
                binaries = load_artifact_binaries(target, artifact_dir, defaults, apps)
            run_stage("run", defaults, apps, binaries, artifact_dir, target, valgrind=valgrind)
    finally:
        for path, contents in backups.items():
            path.write_bytes(contents)
        cleanup_test_files()


def cleanup_test_files() -> None:
    for directory in APP_DIRS:
        for pattern in ("*.e2e.db", "*.bak"):
            for path in directory.glob(pattern):
                path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build and test basic-cli against a bundle")
    parser.add_argument("--bundle-path", type=Path)
    parser.add_argument("--bundle-url", default=os.environ.get("BUNDLE_URL"))
    parser.add_argument("--no-build", action="store_true", default=os.environ.get("NO_BUILD") == "1")
    parser.add_argument(
        "--operation", choices=("all", "validate", "build", "run"), default="all",
        help="run the full native workflow or one reusable CI operation",
    )
    parser.add_argument("--target", choices=declared_targets())
    parser.add_argument("--artifact-dir", type=Path, default=DEFAULT_ARTIFACT_DIR)
    parser.add_argument(
        "--valgrind", action="store_true",
        help="run native example cases under Valgrind and fail on memory errors or leaks",
    )
    args = parser.parse_args()
    if args.bundle_path and args.bundle_url:
        parser.error("--bundle-path and --bundle-url are mutually exclusive")
    target = args.target or detect_native_target()
    artifact_dir = args.artifact_dir.resolve()
    if args.valgrind and shutil.which("valgrind") is None:
        parser.error("--valgrind requires 'valgrind' on PATH")
    if args.valgrind and args.operation not in ("all", "run"):
        parser.error("--valgrind requires an operation that runs example cases")
    if args.operation == "run":
        if target != detect_native_target():
            raise SystemExit(f"Cannot run {target} artifacts on native target {detect_native_target()}")
        run_artifact_cases(target, artifact_dir, valgrind=args.valgrind)
        print("\n=== All native run cases passed! ===")
        return

    if shutil.which(ROC) is None:
        raise SystemExit(f"Roc executable '{ROC}' was not found")
    print(f"Using roc version: {subprocess.check_output([ROC, 'version'], text=True).strip()}")
    if not args.no_build and not args.bundle_path:
        print("\n=== Building platform ===")
        command(sys.executable, ROOT / "scripts" / "build.py", "--target", target)

    operations = {
        "all": {"validate", "build", "run"},
        "validate": {"validate"},
        "build": {"build"},
    }[args.operation]
    if "run" in operations and target != detect_native_target():
        raise SystemExit(f"Cannot run {target} artifacts on native target {detect_native_target()}")

    generated_bundle: Path | None = None
    try:
        if args.bundle_url:
            print(f"\n=== Using provided bundle ===\nBundle: {args.bundle_url}")
            run_suite(args.bundle_url, operations, target, artifact_dir, valgrind=args.valgrind)
        else:
            bundle = args.bundle_path
            if bundle is None:
                print("\n=== Bundling platform ===")
                bundle = generated_bundle = create_bundle()
            elif not bundle.is_absolute():
                bundle = ROOT / bundle
            bundle = bundle.resolve()
            if not bundle.is_file():
                raise SystemExit(f"Bundle does not exist: {bundle}")
            with BundleServer(bundle) as bundle_url:
                print(f"Bundle: {bundle_url}")
                run_suite(bundle_url, operations, target, artifact_dir, valgrind=args.valgrind)
    finally:
        if generated_bundle is not None:
            generated_bundle.unlink(missing_ok=True)
        cleanup_test_files()
    messages = {
        "all": "All native checks and run cases passed",
        "validate": "All source validation stages passed",
        "build": f"All examples built for {target}",
    }
    print(f"\n=== {messages[args.operation]}! ===")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
    except subprocess.TimeoutExpired as error:
        raise SystemExit(f"Timed out after {error.timeout}s: {' '.join(error.cmd)}") from None
