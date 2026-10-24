#!/usr/bin/env bash
# App Store screenshots (iPhone 6.9" and iPad 13", the two sizes App Store Connect requires), iPhone Duo screenshots
# (cover screen, inner screen open flat, half folded) and the README's smaller copies, from the app's demo mode
# (sample stations around Rennes) on fresh simulators.
#
#   scripts/screenshots.sh
#   IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M4)" scripts/screenshots.sh   # other device types
#
# Needs Xcode, XcodeGen and Python 3 with Pillow (pip install pillow). The iPhone Duo ones also need the iOS 27.1
# simulator runtime (xcodebuild -downloadPlatform iOS) and duoctl, which folds the simulator
# (github.com/skarol/duoctl); without them they are skipped. The Screenshots workflow runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

# In CI, a failure names its command and the app's latest crash, as annotations (the logs are not always at hand).
on_error() {
  local status=$? line=$1 command=$2 report
  [ -n "${GITHUB_ACTIONS:-}" ] || return 0
  echo "::error title=screenshots.sh::line $line exited with $status: $command"
  report=$(find "$HOME/Library/Logs/DiagnosticReports" -name 'Carburants*' -newer project.yml 2>/dev/null | tail -1)
  if [ -n "$report" ]; then
    summary=$(grep -E '"exception"|"type"|"signal"|"codes"|"symbol"|"termination"|"indicator"' "$report" | head -40)
    echo "::error title=Carburants crash::${summary//$'\n'/%0A}"
  fi
}
trap 'on_error $LINENO "$BASH_COMMAND"' ERR

IPHONE="${IPHONE:-iPhone 18 Pro Max}"
IPAD="${IPAD:-iPad Pro 13-inch (M5)}"
DELAY="${DELAY:-10}"
BUNDLE=me.jstephan.carburants
OUT=appstore/screenshots

[ -d Carburants.xcodeproj ] || xcodegen --quiet
derived=build/screenshots
xcodebuild build -quiet -project Carburants.xcodeproj -scheme Carburants -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO
app="$derived/Build/Products/Debug-iphonesimulator/Carburants.app"

# shoot <device type> <folder> <screen:appearance>...
shoot() {
  local type="$1" dir="$OUT/$2"
  shift 2
  local udid
  udid=$(xcrun simctl create "Carburants screenshots" "$type")
  trap 'xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  # System in French (status bar date on iPad, system sheets), then boot again for it to apply.
  prepare "$udid" "$dir"

  local n=1 shot screen appearance file
  for shot in "$@"; do
    screen="${shot%%:*}"
    appearance="${shot##*:}"
    xcrun simctl ui "$udid" appearance "$appearance"
    launch "$udid" "$screen"
    # Map tiles come from Apple's servers: the first launch takes longer.
    sleep $((n == 1 ? DELAY * 2 : DELAY))
    file=$(printf '%s/%02d-%s-%s.png' "$dir" "$n" "$screen" "$appearance")
    xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null
    echo "$file"
    n=$((n + 1))
  done
}

# prepare <udid> <folder>: French system (status bar date, system sheets), 9:41 status bar, the app installed.
prepare() {
  local udid="$1" dir="$2"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array fr-FR
  xcrun simctl spawn "$udid" defaults write -g AppleLocale fr_FR
  # Booted again for the language to apply.
  xcrun simctl shutdown "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$app"
  rm -rf "$dir"
  mkdir -p "$dir"
}

# launch <udid> <screen>: the app again, in demo mode on that screen.
launch() {
  xcrun simctl terminate "$1" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$1" "$BUNDLE" -demo YES -demoScreen "$2" -AppleLanguages '(fr)' -AppleLocale fr_FR >/dev/null
}

# iPhone Duo: closed (cover screen), open flat (inner screen, side panel), half folded (list and map on either side
# of the fold). duoctl screenshots the screen in use.
shoot_duo() {
  local dir="$OUT/iphone-duo" runtime udid
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ids = [r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
ok = [i for i in ids if tuple(map(int, i.rsplit("iOS-", 1)[1].split("-")[:2])) >= (27, 1)]
print(ok[-1] if ok else "")')
  if [ -z "$runtime" ] || ! command -v duoctl >/dev/null; then
    echo "No iOS 27.1 runtime or no duoctl: no iPhone Duo screenshots"
    return 0
  fi
  udid=$(xcrun simctl create "Carburants screenshots Duo" "iPhone Duo" "$runtime")
  trap 'xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  prepare "$udid" "$dir"
  export DUOCTL_UDID="$udid"
  xcrun simctl ui "$udid" appearance light

  duoctl close
  launch "$udid" list
  sleep $((DELAY * 2))
  duoctl screenshot "$dir/01-cover.png"
  duoctl open --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/02-open.png"
  # The inner screen stays in landscape, fold down the middle: list on one half, map on the other, held as a
  # book (90°) or set on a table opened wider (120°).
  duoctl half --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/03-half-book.png"
  duoctl hinge 120 --duration 1
  sleep "$DELAY"
  duoctl screenshot "$dir/04-half-tabletop.png"
  ls "$dir"/*.png
}

shoot "$IPHONE" iphone-6.9 list:light detail:light fuels:light list:dark detail:dark
shoot "$IPAD" ipad-13 list:light detail:light list:dark
shoot_duo

python3 scripts/screenshots_post.py "$OUT" screenshots
