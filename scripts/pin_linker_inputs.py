#!/usr/bin/env python3
"""Pin a published linker-input lock and refresh its native license inventory."""
import argparse
import json
from pathlib import Path
import shutil

try:
    from . import linker_inputs as inputs
except ImportError:
    import linker_inputs as inputs


def pin(lock: Path) -> None:
    document = json.loads(lock.read_bytes())
    components = []
    for target in inputs.INVENTORY:
        directory = inputs.ROOT / "platform/targets" / target
        inputs.restore(target, directory, lock=lock)
        manifest = json.loads((directory / "LINKER_INPUTS.json").read_bytes())
        if target == "x64win":
            continue
        for name, version, license_id, license_file, libraries in (
            ("musl libc", manifest["recipe"]["musl"]["version"], "MIT", "musl-COPYRIGHT.txt", ("rcrt1.o", "libc.a")),
            ("LLVM libunwind", manifest["recipe"]["unwind"]["source"], "Apache-2.0 WITH LLVM-exception", "libunwind-LICENSE.TXT", ("libunwind.a",)),
        ):
            destination = inputs.ROOT / "licenses" / license_file
            shutil.copyfile(directory / "licenses" / license_file, destination)
            components.append({
                "name": name, "version": version, "license": license_id, "license_file": license_file,
                "upstream": manifest["recipe"]["musl"]["url"] if name == "musl libc" else f"https://ziglang.org/download/{manifest['recipe']['zig_version']}/",
                "origin": document["targets"][target]["url"],
                "files": {f"platform/targets/{target}/{library}": manifest["files"][library]["sha256"] for library in libraries},
            })
    (inputs.ROOT / "licenses/native-inputs.json").write_bytes(inputs.canonical({"components": components}))
    inputs.LOCK.write_bytes(inputs.canonical(document))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lock", type=Path)
    pin(parser.parse_args().lock)
