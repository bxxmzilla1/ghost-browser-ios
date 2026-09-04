#!/usr/bin/env python3
"""Patch an Instagram .ipa to load GhostTweak.dylib (Blaze-style sideload tweak).

Also strips the bundled Blaze tweak (BlazeUniversal.dylib + CydiaSubstrate.framework)
so only GhostTweak remains. Sideloadbypass2.dylib is kept (it aids sideloading and does
not depend on Blaze).

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

# Load-command name fragments to remove from the main binary (the Blaze tweak + its dep).
REMOVE_LOAD_FRAGMENTS = ("BlazeUniversal", "CydiaSubstrate")
# Files / framework dirs to delete from Frameworks/.
REMOVE_PATHS = ("BlazeUniversal.dylib", "CydiaSubstrate.framework")


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


def patch_binary(binary: Path, install_name: str, remove_fragments: tuple) -> None:
    fat = lief.MachO.parse(str(binary))
    if fat is None:
        raise SystemExit(f"Cannot parse Mach-O: {binary}")

    def patch_slice(macho) -> bool:
        changed = False

        # Remove unwanted load commands (Blaze + Substrate).
        to_remove = [c for c in macho.commands
                     if isinstance(c, lief.MachO.DylibCommand)
                     and any(frag in c.name for frag in remove_fragments)]
        for c in to_remove:
            macho.remove(c)
            print(f"Removed load command: {c.name}")
            changed = True

        # Add GhostTweak (weak load so a bad sign can't crash the app).
        already = any(isinstance(c, lief.MachO.DylibCommand) and c.name == install_name
                      for c in macho.commands)
        if already:
            print(f"Already loads {install_name}")
        else:
            if hasattr(lief.MachO.DylibCommand, "weak_lib"):
                dylib_cmd = lief.MachO.DylibCommand.weak_lib(install_name)
            else:
                dylib_cmd = lief.MachO.DylibCommand.load_dylib(install_name)
            macho.add(dylib_cmd)
            print(f"Injected load command: {install_name}")
            changed = True
        return changed

    if isinstance(fat, lief.MachO.FatBinary):
        changed = False
        for i in range(fat.size):
            if patch_slice(fat.at(i)):
                changed = True
        if changed:
            fat.write(str(binary))
    else:
        if patch_slice(fat):
            fat.write(str(binary))


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

        # Strip the Blaze tweak files.
        for name in REMOVE_PATHS:
            target = frameworks / name
            if target.is_dir():
                shutil.rmtree(target)
                print(f"Deleted Frameworks/{name}")
            elif target.exists():
                target.unlink()
                print(f"Deleted Frameworks/{name}")

        dest_dylib = frameworks / DYLIB_NAME
        shutil.copy2(dylib, dest_dylib)
        print(f"Copied {DYLIB_NAME} -> Frameworks/")

        exe_name = app.stem
        binary = app / exe_name
        if not binary.is_file():
            raise SystemExit(f"Main binary not found: {binary}")

        patch_binary(binary, LOAD_PATH, REMOVE_LOAD_FRAGMENTS)

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
