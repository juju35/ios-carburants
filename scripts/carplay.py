"""Drives the Simulator's CarPlay window for scripts/screenshots.sh (macOS, Simulator app open).

    python scripts/carplay.py open                  # I/O › External Displays › CarPlay
    python scripts/carplay.py tap <udid> <debug.png> # opens Carburants from its icon on the CarPlay screen

The CarPlay scene only starts from the app's icon on the CarPlay screen: the icon is found in a screenshot of that
screen (the app icon, light or dark, matched at every size) and clicked through System Events, which needs
Accessibility for osascript (granted on GitHub's macOS runners). Needs Pillow and NumPy.
"""

import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ICONS = [ROOT / "Carburants/Assets.xcassets/AppIcon.appiconset" / name for name in ("AppIcon.png", "AppIcon-Dark.png")]
# Screenshots are matched at a quarter of their size; above this mean squared difference (0-255), no icon.
REDUCE = 4
MAX_DIFFERENCE = 900.0
# CarPlay screen (800 x 480): where the home screen's icon grid starts, right of the bar of recent apps. In the grid,
# the icon matches at about 900, the app's screens at 1400 and more.
GRID_LEFT = 110
HOME_DIFFERENCE = 1200.0


def osascript(script: str) -> str:
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit(f"osascript: {result.stderr.strip()}")
    return result.stdout.strip()


def open_window() -> None:
    osascript(
        'tell application "Simulator" to activate\n'
        'tell application "System Events" to tell process "Simulator"\n'
        '  click menu item "CarPlay" of menu 1 of menu item "External Displays" of menu 1 '
        'of menu bar item "I/O" of menu bar 1\n'
        "end tell"
    )


def window_bounds() -> tuple[int, int, int, int]:
    text = osascript(
        'tell application "Simulator" to activate\n'
        'tell application "System Events" to tell process "Simulator"\n'
        '  set w to first window whose name contains "CarPlay"\n'
        '  perform action "AXRaise" of w\n'
        "  set {x, y} to position of w\n"
        "  set {width, height} to size of w\n"
        "end tell\n"
        'return (x as text) & "," & (y as text) & "," & (width as text) & "," & (height as text)'
    )
    x, y, width, height = (int(float(value)) for value in text.split(","))
    return x, y, width, height


def box_sums(image: np.ndarray, height: int, width: int) -> np.ndarray:
    """Sum of every height x width window of a 2-D array (top-left corners)."""
    table = np.pad(image.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return table[height:, width:] - table[:-height, width:] - table[height:, :-width] + table[:-height, :-width]


def correlate(image: np.ndarray, template: np.ndarray) -> np.ndarray:
    """Sum of image * template over every window (valid positions), per channel then added up, by FFT."""
    rows, cols = image.shape[0] + template.shape[0], image.shape[1] + template.shape[1]
    total = np.zeros((image.shape[0] - template.shape[0] + 1, image.shape[1] - template.shape[1] + 1))
    for channel in range(3):
        product = np.fft.irfft2(
            np.fft.rfft2(image[:, :, channel], (rows, cols))
            * np.fft.rfft2(template[::-1, ::-1, channel], (rows, cols)),
            (rows, cols),
        )
        total += product[template.shape[0] - 1 : image.shape[0], template.shape[1] - 1 : image.shape[1]]
    return total


def find_icon(screenshot: Image.Image) -> tuple[float, float, float]:
    """Centre of the app icon in the screenshot (pixels) and how far the best match is."""
    small = screenshot.convert("RGB").resize((screenshot.width // REDUCE, screenshot.height // REDUCE))
    image = np.asarray(small, dtype=np.float64)
    squares = box_sums((image**2).sum(2), 1, 1)
    best = (float("inf"), 0.0, 0.0)
    for path in ICONS:
        icon = Image.open(path).convert("RGB")
        for size in range(10, min(image.shape[:2]) // 2):
            # The middle of the icon: no rounded corners, no label.
            margin = max(1, size // 6)
            template = np.asarray(icon.resize((size, size), Image.Resampling.LANCZOS), dtype=np.float64)
            template = template[margin:-margin, margin:-margin]
            height, width = template.shape[:2]
            if height >= image.shape[0] or width >= image.shape[1]:
                break
            difference = box_sums(squares, height, width) - 2 * correlate(image, template) + (template**2).sum()
            difference /= height * width * 3
            y, x = np.unravel_index(np.argmin(difference), difference.shape)
            if difference[y, x] < best[0]:
                best = (float(difference[y, x]), (x + width / 2) * REDUCE, (y + height / 2) * REDUCE)
    return best[1], best[2], best[0]


def tap(udid: str, debug: Path) -> None:
    subprocess.run(
        ["xcrun", "simctl", "io", udid, "screenshot", "--display=external", "--type=png", str(debug)],
        check=True,
        capture_output=True,
    )
    screenshot = Image.open(debug)
    x, y, difference = find_icon(screenshot)
    print(f"Icon at {x:.0f},{y:.0f} of {screenshot.width}x{screenshot.height} (difference {difference:.0f})")
    if difference > MAX_DIFFERENCE:
        raise SystemExit(f"No Carburants icon on the CarPlay screen (best difference {difference:.0f}), see {debug}")
    left, top, width, height = window_bounds()
    # The window is the screen scaled down, under a title bar.
    scale = screenshot.width / width
    title_bar = height - screenshot.height / scale
    point = (round(left + x / scale), round(top + title_bar + y / scale))
    print(f"CarPlay window {left},{top} {width}x{height}: click at {point[0]},{point[1]}")
    # The first click sometimes only brings the window forward: clicked again while the home screen stays.
    for attempt in range(3):
        click(*point)
        for _ in range(4):
            time.sleep(2)
            if not still_home(udid, debug):
                return
        print(f"Click {attempt + 1} did not open the app")
    raise SystemExit(f"The click at {point} did not open Carburants on the CarPlay screen")


def still_home(udid: str, debug: Path) -> bool:
    """The app's big icon is still in the home screen's grid (the small one in the left bar stays there)."""
    after = debug.with_name(debug.stem + "-after.png")
    subprocess.run(
        ["xcrun", "simctl", "io", udid, "screenshot", "--display=external", "--type=png", str(after)],
        check=True,
        capture_output=True,
    )
    screen = Image.open(after)
    grid = screen.crop((GRID_LEFT, 0, screen.width, screen.height))
    return find_icon(grid)[2] <= HOME_DIFFERENCE


def click(x: int, y: int) -> None:
    """A real mouse click at that point of the screen (System Events' "click at" does not reach the CarPlay screen),
    posted by osascript, which has Accessibility."""
    osascript_js(
        'ObjC.import("CoreGraphics"); ObjC.import("Foundation");'
        f"const p = $.CGPointMake({x}, {y});"
        "for (const kind of [$.kCGEventMouseMoved, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {"
        "  $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, kind, p, $.kCGMouseButtonLeft));"
        "  $.NSThread.sleepForTimeInterval(0.15);"
        "}"
    )


def osascript_js(script: str) -> None:
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise SystemExit(f"osascript: {result.stderr.strip()}")


if __name__ == "__main__":
    if sys.argv[1:2] == ["open"]:
        open_window()
    elif sys.argv[1:2] == ["tap"] and len(sys.argv) == 4:
        tap(sys.argv[2], Path(sys.argv[3]))
    else:
        raise SystemExit(__doc__)
