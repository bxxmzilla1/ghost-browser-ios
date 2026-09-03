#!/usr/bin/env python3
"""Patch an Instagram .ipa to load GhostTweak.dylib (Blaze-style sideload tweak).

Usage:
  python patch_instagram.py <input.ipa> <GhostTweak.dylib> [output.ipa]

Works on Windows and macOS (requires: pip install lief).
"""
from __future__ import annotations

import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

try:
    import lief
except ImportError:
    print("Install lief: python -m pip install lief", file=sys.stderr)
    sys.exit(1)

DYLIB_NAME = "GhostTweak.dylib"
LOAD_PATH = f"@executable_path/Frameworks/{DYLIB_NAME}"


def macho_slice(binary_path: Path):
    """Return the arm64 Mach-O slice (handles thin + fat binaries)."""
    parsed = lief.MachO.parse(str(binary_path))
    if parsed is None:
        raise SystemExit(f"Cannot parse Mach-O: {binary_path}")
    if isinstance(parsed, lief.MachO.FatBinary):
        if parsed.size == 0:
            raise SystemExit(f"No slices in fat binary: {binary_path}")
        return parsed.at(0)
    return parsed


def inject_dylib(binary: Path, install_name: str) -> None:
    fat = lief.MachO.parse(str(binary))
    if fat is None:
        raise SystemExit(f"Cannot parse Mach-O: {binary}")

    def patch_slice(macho) -> bool:
        for cmd in macho.commands:
            if isinstance(cmd, lief.MachO.DylibCommand) and cmd.name == install_name:
                print(f"Already loads {install_name}")
                return False
        dylib_cmd = lief.MachO.DylibCommand.load_dylib(install_name)
        macho.add(dylib_cmd)
        return True

    if isinstance(fat, lief.MachO.FatBinary):
        changed = False
        for i in range(fat.size):
            if patch_slice(fat.at(i)):
                changed = True
        if not changed:
            return
        fat.write(str(binary))
    else:
        if not patch_slice(fat):
            return
        fat.write(str(binary))

    print(f"Injected LC_LOAD_DYLIB: {install_name}")


def find_app_dir(root: Path) -> Path:
    payload = root / "Payload"
    apps = list(payload.glob("*.app"))
    if len(apps) != 1:
        raise SystemExit(f"Expected one .app in Payload/, found {len(apps)}")
    return apps[0]


def patch_ipa(ipa_in: Path, dylib: Path, ipa_out: Path) -> None:
    if not ipa_in.is_file():
        raise SystemExit(f"Missing IPA: {ipa_in}")
    if not dylib.is_file():
        raise SystemExit(f"Missing dylib: {dylib}")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        print(f"Extracting {ipa_in.name}...")
        with zipfile.ZipFile(ipa_in, "r") as zf:
            zf.extractall(work)

        app = find_app_dir(work)
        frameworks = app / "Frameworks"
        frameworks.mkdir(exist_ok=True)

        dest_dylib = frameworks / DYLIB_NAME
        shutil.copy2(dylib, dest_dylib)
        print(f"Copied {DYLIB_NAME} -> Frameworks/")

        exe_name = app.stem
        binary = app / exe_name
        if not binary.is_file():
            raise SystemExit(f"Main binary not found: {binary}")

        inject_dylib(binary, LOAD_PATH)

        ipa_out.parent.mkdir(parents=True, exist_ok=True)
        if ipa_out.exists():
            ipa_out.unlink()
        print(f"Packaging {ipa_out.name}...")
        with zipfile.ZipFile(ipa_out, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(work.rglob("*")):
                if path.is_file():
                    zf.write(path, path.relative_to(work).as_posix())

        size_mb = ipa_out.stat().st_size / (1024 * 1024)
        print(f"Done: {ipa_out} ({size_mb:.1f} MB)")


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    ipa_in = Path(sys.argv[1]).resolve()
    dylib = Path(sys.argv[2]).resolve()
    ipa_out = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else ipa_in.with_name(
        ipa_in.stem + "-Ghost" + ipa_in.suffix
    )
    patch_ipa(ipa_in, dylib, ipa_out)


if __name__ == "__main__":
    main()
