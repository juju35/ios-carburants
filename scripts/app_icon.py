"""Draws the app icon (default, dark and tinted appearances) into Carburants/Assets.xcassets/AppIcon.appiconset.

Same pump glyph and green as the Android Automotive app. Run: python scripts/app_icon.py (needs cairosvg).
"""

from pathlib import Path

import cairosvg

OUT = Path(__file__).resolve().parent.parent / "Carburants/Assets.xcassets/AppIcon.appiconset"

# Material "local_gas_station" glyph, 24 x 24.
PUMP = (
    "M19.77,7.23l0.01,-0.01 -3.72,-3.72L15,4.56l2.11,2.11c-0.94,0.36 -1.61,1.26 -1.61,2.33 0,1.38 1.12,2.5 2.5,2.5 "
    "0.36,0 0.69,-0.08 1,-0.21v7.21c0,0.55 -0.45,1 -1,1s-1,-0.45 -1,-1L17,14c0,-1.1 -0.9,-2 -2,-2h-1L14,5c0,-1.1 "
    "-0.9,-2 -2,-2L6,3c-1.1,0 -2,0.9 -2,2v16h10v-7.5h1.5v5c0,1.38 1.12,2.5 2.5,2.5s2.5,-1.12 2.5,-2.5L20.5,9c0,-0.69 "
    "-0.28,-1.32 -0.73,-1.77zM12,10L6,10L6,5h6v5zM18,10c-0.55,0 -1,-0.45 -1,-1s0.45,-1 1,-1 1,0.45 1,1 -0.45,1 -1,1z"
)


def svg(background: str, glyph: str) -> str:
    # The glyph takes ~58% of the icon, centred (the pump's own box is 4..20.5 x 3..21).
    scale = 1024 * 0.58 / 18
    dx = 512 - 12.25 * scale
    dy = 512 - 12 * scale
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3DD69B"/>
      <stop offset="1" stop-color="#0E8A5F"/>
    </linearGradient>
    <linearGradient id="d" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2D31"/>
      <stop offset="1" stop-color="#121416"/>
    </linearGradient>
  </defs>
  {background}
  <path transform="translate({dx:.1f} {dy:.1f}) scale({scale:.3f})" fill="{glyph}" d="{PUMP}"/>
</svg>"""


ICONS = {
    "AppIcon.png": svg('<rect width="1024" height="1024" fill="url(#g)"/>', "#FFFFFF"),
    "AppIcon-Dark.png": svg('<rect width="1024" height="1024" fill="url(#d)"/>', "#3DD69B"),
    # Tinted: grayscale on black, iOS applies the tint.
    "AppIcon-Tinted.png": svg('<rect width="1024" height="1024" fill="#000000"/>', "#FFFFFF"),
}

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, content in ICONS.items():
        cairosvg.svg2png(bytestring=content.encode(), write_to=str(OUT / name))
        print(OUT / name)
