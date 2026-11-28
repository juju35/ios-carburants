"""Copies an Xcode 26 Simulator app, with the frameworks of that Xcode it loads, out of its Xcode (macOS).

    python scripts/package_simulator.py /Applications/Xcode_26.6.app build/Xcode26.app

Xcode 27's Device Hub has no CarPlay screen for simulators, and the runners with Xcode 27 (and the iOS 27 simulator
runtimes the app needs) have no Xcode 26: the Screenshots workflow takes Xcode 26's Simulator app from a macOS 26
runner to the Xcode 27 one, as on a Mac with both Xcodes. Only Simulator.app and the frameworks it loads from inside
its Xcode (found through otool, @rpath, @executable_path and @loader_path, recursively) are copied, at the same place
under the destination, so the copy finds them as it would in its Xcode.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path


def otool(flag: str, binary: Path) -> str:
    return subprocess.run(["otool", flag, str(binary)], capture_output=True, text=True, check=True).stdout


def rpaths(binary: Path) -> list[str]:
    return re.findall(r"cmd LC_RPATH\n\s+cmdsize \d+\n\s+path (.+?) \(offset", otool("-l", binary))


def dependencies(binary: Path) -> list[str]:
    return [line.strip().split(" (")[0] for line in otool("-L", binary).splitlines()[1:]]


def bundle_of(path: Path) -> Path:
    """The .framework, .bundle or .app holding that binary, else the binary itself."""
    for parent in [path, *path.parents]:
        if parent.suffix in {".framework", ".bundle", ".app"}:
            return parent
    return path


def main() -> None:
    xcode, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    simulator = xcode / "Contents/Developer/Applications/Simulator.app"
    main_binary = simulator / "Contents/MacOS/Simulator"
    bundles: set[Path] = {simulator}
    todo, seen = [(main_binary, main_binary.parent)], set()
    while todo:
        binary, executable_dir = todo.pop()
        if binary in seen or not binary.is_file():
            continue
        seen.add(binary)
        searched = [
            p.replace("@executable_path", str(executable_dir)).replace("@loader_path", str(binary.parent))
            for p in rpaths(binary)
        ]
        for dependency in dependencies(binary):
            if dependency.startswith("@rpath/"):
                candidates = [Path(d) / dependency.removeprefix("@rpath/") for d in searched]
            elif dependency.startswith("@executable_path/"):
                candidates = [executable_dir / dependency.removeprefix("@executable_path/")]
            elif dependency.startswith("@loader_path/"):
                candidates = [binary.parent / dependency.removeprefix("@loader_path/")]
            else:
                candidates = [Path(dependency)]
            for found in (c.resolve() for c in candidates):
                if found.is_file() and found.is_relative_to(xcode):
                    bundles.add(bundle_of(found))
                    todo.append((found, executable_dir))
                    break
    for bundle in sorted(bundles):
        target = out / bundle.relative_to(xcode)
        print(bundle.relative_to(xcode))
        target.parent.mkdir(parents=True, exist_ok=True)
        if bundle.is_dir():
            shutil.copytree(bundle, target, symlinks=True, dirs_exist_ok=True)
        else:
            shutil.copy2(bundle, target)


if __name__ == "__main__":
    main()
