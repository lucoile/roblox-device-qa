#!/usr/bin/env python3
"""Build the optional pinned Rojo dependency locally; never contacts Studio."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

from prepare_bootstrap import PINNED_BUNDLE_SHA256

ROOT = Path(__file__).resolve().parent.parent
RELEASE_URL = "https://github.com/rojo-rbx/rojo/releases/download/v7.7.0/Rojo.rbxm"
RELEASE_SHA256 = "214e5ad84ccdc88f873e0467b6724e4ea9ada8ea340fcb9d4397cb899a67c83f"
MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024


def checked_digest(path, expected):
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f"Checksum mismatch for {path.name}: expected {expected}, got {actual}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lune", default="lune", help="Lune 0.10.3 executable (default: PATH)")
    parser.add_argument("--source", type=Path, help="Use an already downloaded official Rojo.rbxm")
    args = parser.parse_args()
    executable = shutil.which(args.lune)
    if executable is None:
        parser.error("Lune not found. Run rokit install from this repository, or pass --lune PATH.")
    version = subprocess.run([executable, "--version"], cwd=ROOT, check=True,
                             capture_output=True, text=True, timeout=15).stdout.strip()
    if version != "lune 0.10.3":
        parser.error(f"Lune 0.10.3 is required for the pinned bundle; found {version!r}")
    license_path = ROOT / "LICENSES" / "MPL-2.0.txt"
    if not license_path.is_file():
        parser.error("Missing LICENSES/MPL-2.0.txt; install the complete skill repository")

    assets = ROOT / "assets"
    assets.mkdir(exist_ok=True)
    # Stage on the destination filesystem so replacement is atomic after verification.
    with tempfile.TemporaryDirectory(prefix=".rojo-setup-", dir=assets) as scratch:
        scratch = Path(scratch)
        original = scratch / "Rojo.rbxm"
        if args.source:
            shutil.copyfile(args.source, original)
        else:
            request = urllib.request.Request(RELEASE_URL, headers={"User-Agent": "roblox-device-qa"})
            with urllib.request.urlopen(request, timeout=30) as response:
                data = response.read(MAX_DOWNLOAD_BYTES + 1)
            if len(data) > MAX_DOWNLOAD_BYTES:
                raise ValueError("Rojo release exceeds the expected download size limit")
            original.write_bytes(data)
        checked_digest(original, RELEASE_SHA256)
        built = scratch / "RojoHeadless-7.7.0.rbxm"
        subprocess.run([executable, "run", str(ROOT / "scripts" / "build_rojo.luau"),
                        str(original), str(built)], cwd=ROOT, check=True, timeout=60)
        checked_digest(built, PINNED_BUNDLE_SHA256)
        shutil.copyfile(license_path, scratch / "LICENSE.txt")
        os.replace(scratch / "LICENSE.txt", assets / "LICENSE.txt")
        os.replace(built, assets / built.name)
    print(f"Ready: {assets / 'RojoHeadless-7.7.0.rbxm'}")
    print(f"SHA-256: {PINNED_BUNDLE_SHA256}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Setup failed: {error}") from error
