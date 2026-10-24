"""Finishes scripts/screenshots.sh's captures.

- App Store Connect refuses screenshots with an alpha channel: the PNGs are flattened in place.
- The README shows smaller copies (screenshots/, 600 px wide for iPhone, 1000 px for iPad).

Usage: python scripts/screenshots_post.py appstore/screenshots screenshots
"""

import sys
from pathlib import Path

from PIL import Image

README_WIDTH = {"iphone-6.9": 600, "ipad-13": 1000}


def main(source: Path, readme: Path) -> None:
    readme.mkdir(exist_ok=True)
    for old in readme.glob("*.png"):
        old.unlink()
    for folder, width in README_WIDTH.items():
        for path in sorted((source / folder).glob("*.png")):
            image = Image.open(path).convert("RGB")
            image.save(path, optimize=True)
            height = round(image.height * width / image.width)
            small = image.resize((width, height), Image.Resampling.LANCZOS)
            target = readme / f"{folder.split('-')[0]}-{path.name}"
            small.save(target, optimize=True)
            print(target)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
