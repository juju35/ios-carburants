"""Drives the Simulator's CarPlay window for scripts/screenshots.sh (macOS, Simulator app open).

    python scripts/carplay.py open                  # I/O › External Displays › CarPlay
    python scripts/carplay.py tap <udid> <debug.png> # opens Carburants from its icon on the CarPlay screen
    python scripts/carplay.py click <udid> <x> <y>   # clicks that point of the CarPlay screen (800 x 480)

The CarPlay scene only starts from the app's icon on the CarPlay screen: the icon is found in a screenshot of that
screen (the app icon, light or dark, matched at every size) and clicked through System Events, which needs
Accessibility for osascript (granted on GitHub's macOS runners). Needs Pillow and NumPy.
"""

import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICONS = [ROOT / "Carburants/Assets.xcassets/AppIcon.appiconset" / name for name in ("AppIcon.png", "AppIcon-Dark.png")]
# Screenshots are matched at a quarter of their size; above this mean squared difference (0-255), no icon.
REDUCE = 4
MAX_DIFFERENCE = 900.0
# CarPlay screen (800 x 480): where the home screen's icon grid starts, right of the bar of recent apps. In the grid,
# the icon matches at about 900, the app's screens at 1400 and more.
GRID_LEFT = 110
HOME_DIFFERENCE = 1200.0
# The left bar's home button, and the mean edge strength above which the app's screen is drawn (about 2 while blank,
# 14 with the map or a list).
HOME_BUTTON = (52, 428)
MIN_EDGES = 5.0


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


def arrange_windows() -> None:
    """The CarPlay window top left, the device's window to its right: where they overlap, a click meant for the CarPlay
    screen can land on the device's screen instead."""
    osascript(
        'tell application "Simulator" to activate\n'
        'tell application "System Events" to tell process "Simulator"\n'
        '  set carplay to first window whose name contains "CarPlay"\n'
        "  set position of carplay to {0, 40}\n"
        "  set {width, height} to size of carplay\n"
        '  repeat with other in (windows whose name does not contain "CarPlay")\n'
        "    set position of other to {width + 60, 40}\n"
        "  end repeat\n"
        '  perform action "AXRaise" of carplay\n'
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
    """Back to the home screen if an app shows, then the app's icon in the grid until the app has drawn its screen."""
    screen = capture(udid, debug)
    if grid_icon(screen) is None:
        print("Not on the home screen: home button")
        click_on(HOME_BUTTON, screen)
        for _ in range(5):
            time.sleep(2)
            screen = capture(udid, debug)
            if grid_icon(screen) is not None:
                break
    icon = grid_icon(screen)
    if icon is None:
        raise SystemExit(f"No Carburants icon on the CarPlay home screen, see {debug}")
    print(f"Icon at {icon[0]:.0f},{icon[1]:.0f}")
    arrange_windows()
    # A click on a window that is not key only makes it key: raising the window again before each try (as
    # click_on does) can eat every click. Every other try clicks the same point again without raising it.
    after = debug.with_name(debug.stem + "-after.png")
    point = (0, 0)
    for attempt in range(4):
        if attempt % 2 == 0:
            point = click_on(icon, screen)
        else:
            print(f"Same point again, window not raised, session event tap: {point}")
            click(*point, session=True)
        for _ in range(6):
            time.sleep(2)
            screen = capture(udid, after)
            if grid_icon(screen) is None and drawn(screen):
                return
        print(f"Click {attempt + 1}: the app's screen did not show")
    # The whole Mac screen, to see where the clicks went.
    subprocess.run(["screencapture", "-x", "-C", str(debug.with_name("mac-screen.png"))], check=False)
    raise SystemExit(f"The click at {point} did not open Carburants on the CarPlay screen, see {after}")


def click_on(point: tuple[float, float], screen: Image.Image) -> tuple[int, int]:
    """Clicks that point of the CarPlay screen. The window is brought forward just before: a click that comes several
    seconds after (the icon search takes that long) does not reach the CarPlay screen."""
    window = window_bounds()
    target = to_window(point, screen, window)
    print(f"CarPlay window {window}: click at {target}")
    click(*target)
    return target


def click_inside(udid: str, x: float, y: float) -> None:
    """A click in the app (a tab, a row), then until its new screen is drawn."""
    path = ROOT / "build/carplay-debug/click.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    before = capture(udid, path)
    click_on((x, y), before)
    for _ in range(8):
        time.sleep(1)
        screen = capture(udid, path)
        if drawn(screen) and changed(before, screen):
            return
    raise SystemExit(f"The click at {x:.0f},{y:.0f} changed nothing on the CarPlay screen, see {path}")


def changed(before: Image.Image, after: Image.Image) -> bool:
    difference = np.abs(
        np.asarray(before.convert("L"), dtype=np.float64) - np.asarray(after.convert("L"), dtype=np.float64)
    )
    return float((difference > 64).mean()) > 0.02


def capture(udid: str, path: Path) -> Image.Image:
    subprocess.run(
        ["xcrun", "simctl", "io", udid, "screenshot", "--display=external", "--type=png", str(path)],
        check=True,
        capture_output=True,
    )
    return Image.open(path)


def grid_icon(screen: Image.Image) -> tuple[float, float] | None:
    """Centre of the app's big icon in the home screen's grid (the small one in the left bar stays there)."""
    x, y, difference = find_icon(screen.crop((GRID_LEFT, 0, screen.width, screen.height)))
    return (x + GRID_LEFT, y) if difference <= HOME_DIFFERENCE else None


def drawn(screen: Image.Image) -> bool:
    """The app's templates are drawn: right of the left bar, an app that is still starting is a blank background."""
    area = screen.convert("L").crop((GRID_LEFT, 0, screen.width, screen.height))
    return float(np.asarray(area.filter(ImageFilter.FIND_EDGES), dtype=np.float64).mean()) > MIN_EDGES


def to_window(point: tuple[float, float], screen: Image.Image, window: tuple[int, int, int, int]) -> tuple[int, int]:
    """A point of the CarPlay screen on the Mac's screen: the window is the screen scaled down, under a title bar."""
    left, top, width, height = window
    scale = screen.width / width
    title_bar = height - screen.height / scale
    return round(left + point[0] / scale), round(top + title_bar + point[1] / scale)


def click(x: int, y: int, session: bool = False) -> None:
    """A real mouse click at that point of the screen (System Events' "click at" does not reach the CarPlay screen),
    posted by osascript, which has Accessibility: to the HID event tap, or the session's one. The click state is set as
    a real click's: some runs ignore every click on the CarPlay screen without it."""
    tap = "$.kCGSessionEventTap" if session else "$.kCGHIDEventTap"
    osascript_js(
        'ObjC.import("CoreGraphics"); ObjC.import("Foundation");'
        f"const p = $.CGPointMake({x}, {y});"
        "for (const kind of [$.kCGEventMouseMoved, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {"
        "  const event = $.CGEventCreateMouseEvent(null, kind, p, $.kCGMouseButtonLeft);"
        "  $.CGEventSetIntegerValueField(event, $.kCGMouseEventClickState, 1);"
        f"  $.CGEventPost({tap}, event);"
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
    elif sys.argv[1:2] == ["click"] and len(sys.argv) == 5:
        click_inside(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))
    else:
        raise SystemExit(__doc__)
