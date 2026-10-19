#!/usr/bin/env python3
"""Check the public OS-witness boundary with the repository's pinned Roc.

These are compiler checks, so every OS branch is checked on every host. No
application is executed and no native host needs to be built. Set ROC to use
the pinned compiler, as with scripts/test.py.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Rejected:
    name: str
    source: str
    diagnostics: tuple[str, ...]


POSITIVE = """
    import pf.System
    import pf.Signal
    import pf.Cmd
    import pf.IOErr

    unix_from_target : System.Target -> Try(System.Unix, [Windows])
    unix_from_target = |target|
        match target.os() {
            Linux(linux) => Ok(linux.unix())
            MacOS(macos) => Ok(macos.unix())
            Windows(_) => Err(Windows)
        }

    catch_unix! : System.Unix => Try({}, [SignalErr(IOErr)])
    catch_unix! = |unix| Signal.catch!([Interrupt, Terminate(unix)])

    replace! : System.Unix => Try({}, [CmdErr(Cmd.Err), Interrupted])
    replace! = |unix| Cmd.exec!(unix, "/bin/true", [])

    main! = |_| {
        target = System.target!()
        _arch = target.arch()
        match unix_from_target(target) {
            Ok(unix) => catch_unix!(unix)?
            Err(Windows) => Signal.catch!([Interrupt])?
        }
        Ok({})
    }
"""


def rejected_cases() -> list[Rejected]:
    cases = []
    for witness in ("Unix", "Linux", "MacOS", "Windows"):
        cases.append(Rejected(
            f"cannot-construct-{witness.lower()}",
            f"""
                import pf.System
                main! = |_| {{
                    _forged : System.{witness}
                    _forged = System.{witness}.{{ proof: 0 }}
                    Ok({{}})
                }}
            """,
            ("cannot use opaque nominal type", f"System.{witness}"),
        ))
    cases.extend([
        Rejected("cannot-construct-target", """
            import pf.System
            main! = |_| {
                _forged = System.Target.{
                    architecture: X64,
                    operating_system: Windows({ proof: 0 }),
                }
                Ok({})
            }
        """, ("cannot use opaque nominal type", "System.Target")),
        Rejected("record-is-not-unix", """
            import pf.System
            forge : System.Unix
            forge = { proof: 0 }
            main! = |_| Ok({})
        """, ("type mismatch", "System.Unix")),
        Rejected("windows-is-not-unix", """
            import pf.System
            as_unix : System.Windows -> System.Unix
            as_unix = |windows| windows
            main! = |_| Ok({})
        """, ("type mismatch", "System.Windows", "System.Unix")),
        Rejected("windows-has-no-unix-method", """
            import pf.System
            as_unix : System.Windows -> System.Unix
            as_unix = |windows| windows.unix()
            main! = |_| Ok({})
        """, ("missing method", "System.Windows", "unix")),
        Rejected("exec-requires-witness", """
            import pf.Cmd
            main! = |_| Cmd.exec!("/bin/true", [])
        """, ("too few args", "System.Unix")),
        Rejected("terminate-requires-witness", """
            import pf.Signal
            main! = |_| Signal.catch!([Terminate])
        """, ("type mismatch", "Signal.Request")),
        Rejected("exec-rejects-windows-witness", """
            import pf.System
            import pf.Cmd
            main! = |_| {
                match System.target!().os() {
                    Windows(windows) => Cmd.exec!(windows, "/bin/true", [])
                    _ => Ok({})
                }
            }
        """, ("type mismatch", "System.Windows", "System.Unix")),
        Rejected("terminate-rejects-windows-witness", """
            import pf.System
            import pf.Signal
            main! = |_| {
                match System.target!().os() {
                    Windows(windows) => Signal.catch!([Terminate(windows)])
                    _ => Ok({})
                }
            }
        """, ("type mismatch", "System.Windows", "Signal.Request")),
        Rejected("unix-has-no-decoder", """
            import pf.System
            decoded : Try(System.Unix, _)
            decoded = Json.parse("{\\"proof\\":0}")
            main! = |_| Ok({})
        """, ("missing method", "System.Unix")),
        Rejected("unix-has-no-encoder", """
            import pf.System
            encode : System.Unix -> Str
            encode = |unix| Json.to_str(unix)
            main! = |_| Ok({})
        """, ("missing method", "System.Unix")),
        Rejected("discovery-is-effectful", """
            import pf.System
            pure_target : {} -> System.Target
            pure_target = |_| System.target!()
            main! = |_| Ok({})
        """, ("type mismatch", "effectful, but a pure function is expected")),
        Rejected("host-is-private", """
            import pf.Host
            main! = |_| Host.signal_catch!([Interrupt])
        """, ("package module is private", "pf.Host")),
    ])
    return cases


def check(roc: str, app: Path, header: str, source: str) -> subprocess.CompletedProcess[str]:
    app.write_text(header + textwrap.dedent(source).lstrip(), encoding="utf-8")
    return subprocess.run(
        [roc, "check", str(app), "--no-cache"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
        env={**os.environ, "NO_COLOR": "1"},
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", type=Path, default=ROOT / "platform" / "main.roc")
    args = parser.parse_args()
    platform = args.platform.resolve(strict=True)
    roc = os.environ.get("ROC", "roc")
    # Roc rejects absolute platform specifications. A temporary directory on
    # the checkout's volume also keeps this relative reference valid on Windows.
    with tempfile.TemporaryDirectory(prefix=".system-api-", dir=platform.parent.parent) as tmp:
        work = Path(tmp)
        local_platform = Path(os.path.relpath(platform, work)).as_posix()
        header = f'app [main!] {{ pf: platform "{local_platform}" }}\n\n'
        positive = check(roc, work / "generic-helper.roc", header, POSITIVE)
        if positive.returncode != 0:
            raise SystemExit(f"Generic witness helpers must compile:\n{positive.stdout}")
        print("PASS generic witness helpers and narrowing", flush=True)
        cases = rejected_cases()
        for case in cases:
            result = check(roc, work / f"{case.name}.roc", header, case.source)
            output = result.stdout.casefold()
            if result.returncode == 0 or any(text.casefold() not in output for text in case.diagnostics):
                raise SystemExit(
                    f"{case.name}: expected rejection containing {case.diagnostics!r}, "
                    f"got exit {result.returncode}:\n{result.stdout}"
                )
            print(f"PASS {case.name}", flush=True)
        print(f"Verified OS witness API: 1 positive and {len(cases)} negative checks", flush=True)


if __name__ == "__main__":
    main()
