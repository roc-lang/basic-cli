"""Manifest rejection tests, plus executable ABI checks on Windows."""
import json
import argparse
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import build, bundle, windows_runtime as runtime


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for name in (*runtime.LIBRARIES, "host.lib"):
            (self.output / name).write_bytes(name.encode())
        license_file = runtime.notice(self.output, "license.txt", b"original license")
        components = {"fixture": {
            "license": "MIT", "license_files": [license_file],
            "redistribution_basis": "fixture", "sources": [{"sha256": "fixture"}],
            "build_commands": [["fixture"]],
        }}
        runtime.write_manifest(self.output, components,
                               {name: "fixture" for name in (*runtime.LIBRARIES, "host.lib")})

    def test_complete_inventory_returns_notices(self):
        self.assertEqual(len(runtime.validate(self.output)), 2)

    def test_tampered_library_rejected(self):
        (self.output / "host.lib").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "library hash mismatch"):
            runtime.validate(self.output)

    def test_tampered_notice_rejected(self):
        (self.output / "licenses/license.txt").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "license hash mismatch"):
            runtime.validate(self.output)

    def test_missing_and_empty_inputs_rejected(self):
        (self.output / runtime.LIBRARIES[0]).write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_unexpected_sdk_archive_rejected(self):
        (self.output / "libcmt.lib").write_bytes(b"unapproved")
        with self.assertRaisesRegex(ValueError, "inventory mismatch"):
            runtime.validate(self.output)

    def test_license_path_escape_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        manifest["components"]["fixture"]["license_files"] = ["../outside.txt"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "invalid Windows license"):
            runtime.validate(self.output)

    def test_missing_rights_evidence_rejected(self):
        path = self.output / runtime.MANIFEST_NAME
        manifest = json.loads(path.read_text())
        del manifest["components"]["fixture"]["redistribution_basis"]
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "redistribution_basis"):
            runtime.validate(self.output)

    def test_stdcall_normalization_preserves_ordinals(self):
        definition = runtime.normalize_definition("EXPORTS\n Foo@8 @123\n Bar @4 DATA\n")
        self.assertIn("Foo @123", definition)
        self.assertIn("Bar @4 DATA", definition)

    def test_inherited_rust_flags_preserved_and_dynamic_crt_selected(self):
        with patch.dict(os.environ, {"CARGO_ENCODED_RUSTFLAGS": "-Ctarget-feature=+crt-static\x1f-Cdebuginfo=1"}), \
             patch.object(build.shutil, "which", return_value="clang-cl"):
            env, _ = build.windows_build_env()
        self.assertEqual(env["CARGO_ENCODED_RUSTFLAGS"].split("\x1f"),
                         ["-Ctarget-feature=+crt-static", "-Cdebuginfo=1", "-Ctarget-feature=-crt-static"])

    def test_bundle_transfers_every_hashed_notice_and_restores_local_license(self):
        root = self.output / "repo"
        platform = root / "platform"
        windows = platform / "targets/x64win"
        windows.parent.mkdir(parents=True)
        import shutil
        shutil.copytree(self.output / "licenses", windows / "licenses")
        for name in (*runtime.LIBRARIES, "host.lib", runtime.MANIFEST_NAME):
            shutil.copy2(self.output / name, windows / name)
        (platform / "main.roc").write_text('x64win: { inputs: ["host.lib", app, "msvc_runtime.lib"] }\n')
        (root / "LICENSE").write_text("root license")
        (root / "THIRD_PARTY_LICENSES.md").write_text("root notices")
        (platform / "LICENSE").write_text("existing local license")
        with patch.object(bundle, "ROOT", root), patch.object(bundle, "PLATFORM_DIR", platform), \
             patch.object(bundle.subprocess, "run") as run:
            bundle.bundle(argparse.Namespace(output_dir=root / "dist", stub_missing_targets=False), [])
        arguments = run.call_args.args[0]
        self.assertIn("targets/x64win/licenses/license.txt", arguments)
        self.assertIn("targets/x64win/PROVENANCE.json", arguments)
        self.assertIn("LICENSE", arguments)
        self.assertIn("THIRD_PARTY_LICENSES.md", arguments)
        self.assertEqual((platform / "LICENSE").read_text(), "existing local license")
        self.assertFalse((platform / "THIRD_PARTY_LICENSES.md").exists())

    def test_declared_windows_inputs_match_producer_inventory(self):
        declared = {p.name for p in bundle.declared_target_inputs() if p.parent.name == "x64win"}
        self.assertEqual(declared, set(runtime.LIBRARIES) | {"host.lib"})


@unittest.skipUnless(os.name == "nt", "native Windows ABI execution")
class WindowsRuntimeTests(unittest.TestCase):
    def test_actual_host_links_without_sdk_or_vc_runtime_archives(self):
        inputs = runtime.ROOT / "platform/targets/x64win"
        runtime.validate(inputs)
        scratch = runtime.ROOT / "target/windows-host-fixture"
        scratch.mkdir(parents=True, exist_ok=True)
        source = scratch / "app.c"
        # MSVC passes this RocList argument indirectly; the smoke app ignores it.
        source.write_text("int roc_main(void *args) { (void)args; return 37; }\n")
        obj, exe = scratch / "app.obj", scratch / "app.exe"
        subprocess.run(["zig", "cc", "-target", "x86_64-windows-msvc", "-c", str(source), "-o", str(obj)], check=True)
        subprocess.run(["zig", "lld-link", "/nodefaultlib", "/subsystem:console",
                        "/entry:mainCRTStartup", "/machine:x64", "/opt:ref", f"/out:{exe}",
                        str(obj), str(inputs / "host.lib"),
                        *(str(inputs / name) for name in runtime.LIBRARIES)], check=True)
        imports = subprocess.check_output([
            str(build.find_llvm_strip().with_name("llvm-readobj.exe")), "--coff-imports", str(exe)], text=True)
        self.assertNotIn("vcruntime", imports.lower())
        self.assertNotIn("msvcp", imports.lower())
        self.assertEqual(subprocess.run([str(exe)], timeout=20).returncode, 37)

    def test_startup_tls_initializers_cookie_and_metadata(self):
        inputs = runtime.ROOT / "platform/targets/x64win"
        runtime.validate(inputs)
        scratch = runtime.ROOT / "target/windows-runtime-fixture"
        scratch.mkdir(parents=True, exist_ok=True)
        for fail_initializer in (False, True):
            obj = scratch / "fixture.obj"
            exe = scratch / "fixture.exe"
            compile_args = ["zig", "cc", "-target", "x86_64-windows-msvc", "-O2",
                            "-fstack-protector-strong", "-c",
                            str(runtime.SOURCE_DIR / "runtime_fixture.c"), "-o", str(obj)]
            if fail_initializer:
                compile_args.append("-DFAIL_INITIALIZER")
            subprocess.run(compile_args, check=True)
            subprocess.run(["zig", "lld-link", "/nodefaultlib", "/subsystem:console",
                            "/entry:mainCRTStartup", "/machine:x64", "/opt:ref",
                            f"/out:{exe}", str(obj),
                            *(str(inputs / name) for name in runtime.LIBRARIES)], check=True)
            readobj = build.find_llvm_strip().with_name("llvm-readobj.exe")
            imports = subprocess.check_output([str(readobj), "--coff-imports", str(exe)], text=True)
            self.assertNotIn("vcruntime", imports.lower())
            self.assertNotIn("msvcp", imports.lower())
            result = subprocess.run([str(exe), "a b"], timeout=20)
            self.assertEqual(result.returncode, 255 if fail_initializer else 37)
            if not fail_initializer:
                result = subprocess.run([str(exe), "fail"], timeout=20)
                self.assertEqual(result.returncode & 0xffffffff, 0xc0000409)


if __name__ == "__main__":
    unittest.main()
