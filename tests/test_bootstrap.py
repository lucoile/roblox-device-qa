import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "prepare_bootstrap.py"
BUNDLE = ROOT / "assets" / "RojoHeadless-7.7.0.rbxm"
CONTROLLER = ROOT / "scripts" / "Controller.luau"
LUNE = os.environ.get("LUNE", "lune")
spec = importlib.util.spec_from_file_location("bootstrap", SCRIPT)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def generate(self, output, bundle=BUNDLE):
        return subprocess.run([sys.executable, str(SCRIPT), str(output),
                               "--bundle", str(bundle), "--controller", str(CONTROLLER)],
                              capture_output=True, text=True, timeout=15)

    def test_pinned_bundle_roundtrip(self):
        self.assertTrue(BUNDLE.is_file(), "Run python3 scripts/setup_rojo.py first")
        payload = BUNDLE.read_bytes()
        self.assertEqual(hashlib.sha256(payload).hexdigest(), bootstrap.PINNED_BUNDLE_SHA256)
        with tempfile.TemporaryDirectory(prefix="rojo qa ") as directory:
            output = Path(directory) / "bootstrap with spaces"
            result = self.generate(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["bundleSha256"], bootstrap.PINNED_BUNDLE_SHA256)
            self.assertEqual(manifest["steps"][0], "00_begin.luau")
            self.assertEqual(manifest["steps"][-1], "99_finish.luau")
            parts = []
            for name in manifest["steps"][1:-1]:
                source = (output / name).read_text()
                encoded = json.loads(re.search(r"^part.Value = (.+)$", source, re.M)[1])
                self.assertLessEqual(len(encoded), 180000)
                parts.append(encoded)
            self.assertEqual(base64.b64decode("".join(parts), validate=True), payload)

    def test_bad_checksum_creates_no_bootstrap(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            bad = directory / "corrupt.rbxm"
            bad.write_bytes(b"not the pinned release")
            output = directory / "output"
            result = self.generate(output, bad)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("checksum", result.stderr.lower())
            self.assertFalse(output.exists())

    def test_luau_strings_preserve_content(self):
        values = ["", "plain", "\nleading newline", "\r\nwindows newline", "a]]b]=]c]==]d",
                  "return 'hello'\n", "Unicode: café ☕", '\\n\\"', "\x00\x01123\x7f"]
        with tempfile.TemporaryDirectory(prefix="rojo strings ") as directory:
            cases = Path(directory) / "cases.json"
            cases.write_text(json.dumps([{"value": text, "literal": bootstrap.luau_string(text)}
                                         for text in values]))
            result = subprocess.run([LUNE, "run", str(ROOT / "tests" / "strings.luau"), str(cases)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_setup_rejects_corruption_without_replacing_bundle(self):
        with tempfile.TemporaryDirectory(prefix="rojo install ") as directory:
            directory = Path(directory)
            shutil.copytree(ROOT / "scripts", directory / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
            shutil.copytree(ROOT / "LICENSES", directory / "LICENSES")
            shutil.copyfile(ROOT / "rokit.toml", directory / "rokit.toml")
            (directory / "assets").mkdir()
            destination = directory / "assets" / BUNDLE.name
            destination.write_bytes(b"previous installation")
            invalid = directory / "invalid.rbxm"
            invalid.write_bytes(b"corrupt")
            result = subprocess.run([sys.executable, str(directory / "scripts" / "setup_rojo.py"),
                                     "--source", str(invalid), "--lune", LUNE], cwd=ROOT,
                                    capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Checksum mismatch", result.stderr)
            self.assertEqual(destination.read_bytes(), b"previous installation")
            self.assertEqual(sorted(p.name for p in (directory / "assets").iterdir()), [BUNDLE.name])


if __name__ == "__main__":
    unittest.main()
