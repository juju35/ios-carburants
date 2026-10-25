#!/usr/bin/env bash
# App Store screenshots (iPhone 6.9" and iPad 13", the two sizes App Store Connect requires), iPhone Duo screenshots
# (cover screen, inner screen open flat, half folded), CarPlay screenshots and the README's smaller copies, from the app's demo mode
# (sample stations around Rennes) on fresh simulators.
#
#   scripts/screenshots.sh
#   IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M4)" scripts/screenshots.sh   # other device types
#
# Needs Xcode, XcodeGen and Python 3 with Pillow and NumPy (pip install pillow numpy). The iPhone Duo ones also need the iOS 27.1
# simulator runtime (xcodebuild -downloadPlatform iOS) and duoctl, which folds the simulator
# (github.com/skarol/duoctl); without them they are skipped. The Screenshots workflow runs it.
set -Eeuo pipefail
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

# APP=path/to/Carburants.app uses that build (the Screenshots workflow builds once, on Xcode 27, for every job).
app="${APP:-}"
if [ -z "$app" ]; then
  [ -d Carburants.xcodeproj ] || xcodegen --quiet
  derived=build/screenshots
  # Signed to run locally with the CarPlay entitlement: the Simulator's CarPlay screen only lists apps that have it.
  # Its errors as annotations in CI.
  mkdir -p build
  if ! xcodebuild build -quiet -project Carburants.xcodeproj -scheme Carburants -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    CARBURANTS_ENTITLEMENTS=Config/CarburantsCarPlay.entitlements >build/screenshots-build.log 2>&1; then
    cat build/screenshots-build.log
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      errors=$(grep -E "error|requires|Signing" build/screenshots-build.log | head -20)
      echo "::error title=xcodebuild::${errors//$'\n'/%0A}"
    fi
    exit 1
  fi
  app="$derived/Build/Products/Debug-iphonesimulator/Carburants.app"
fi

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

# launch <udid> <screen> [arguments...]: the app again, in demo mode on that screen. Right after a boot or a fold,
# the system may refuse to open apps for a moment (simctl exits with 149): tried again a few times.
launch() {
  local attempt udid="$1" screen="$2"
  shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  for attempt in 1 2 3 4 5; do
    if xcrun simctl launch "$udid" "$BUNDLE" -demo YES -demoScreen "$screen" -AppleLanguages '(fr)' -AppleLocale fr_FR \
      "$@" >/dev/null; then
      return 0
    fi
    echo "Launch $attempt refused on $udid ($screen), trying again"
    sleep 5
  done
  return 1
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

# CarPlay: the Simulator's CarPlay screen (I/O › External Displays › CarPlay). Xcode 27's Device Hub has no CarPlay
# for simulators, so this uses the Simulator app of Xcode 26 (CARPLAY_SIMULATOR to choose another) on an iOS 26
# simulator; the Screenshots workflow runs it on a macOS 26 runner, with the app built by Xcode 27. The app's CarPlay scene only starts from its icon there, so for each screen the app is launched
# in demo mode on the iPhone, then its icon is tapped on the CarPlay screen (scripts/carplay.py). Needs Accessibility
# for osascript; skipped, the previous screenshots kept, when something is missing.
CARPLAY_IPHONE="${CARPLAY_IPHONE:-iPhone 17 Pro Max}"
shoot_carplay() {
  local dir="$OUT/carplay" tmp udid n=1 screen simulator runtime opened
  # The selected Xcode's when it still has one (Xcode 26), else the latest installed Xcode 26's.
  simulator="${CARPLAY_SIMULATOR:-$(ls -d "$(xcode-select -p)/Applications/Simulator.app" \
    /Applications/Xcode_26*.app/Contents/Developer/Applications/Simulator.app 2>/dev/null | head -1 || true)}"
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ids = [r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and "SimRuntime.iOS-26-" in r["identifier"]]
print(sorted(ids)[-1] if ids else "")')
  if [ -z "$simulator" ] || [ ! -d "$simulator" ] || [ -z "$runtime" ]; then
    echo "::warning title=CarPlay screenshots::no Xcode 26 Simulator app ($simulator) or iOS 26 runtime ($runtime), previous ones kept. Installed: $(ls -d /Applications/Xcode*.app 2>/dev/null | tr '\n' ' '), $(xcrun simctl list runtimes | grep -c iOS) iOS runtimes"
    return 0
  fi
  echo "CarPlay: $simulator, $runtime"
  tmp=$(mktemp -d)
  mkdir -p build/carplay-debug
  udid=$(xcrun simctl create "Carburants screenshots CarPlay" "$CARPLAY_IPHONE" "$runtime")
  trap 'osascript -e "quit app \"Simulator\"" >/dev/null 2>&1 || true; xcrun simctl delete "$udid" >/dev/null 2>&1 || true' RETURN
  prepare "$udid" "$tmp"
  xcrun simctl ui "$udid" appearance light
  if ! opened=$(open "$simulator" --args -CurrentDeviceUDID "$udid" 2>&1); then
    echo "::warning title=CarPlay screenshots::could not open $simulator: ${opened//$'\n'/ }"
    return 0
  fi
  sleep "$DELAY"
  if ! opened=$(python3 scripts/carplay.py open 2>&1); then
    echo "::warning title=CarPlay screenshots::could not open the Simulator's CarPlay screen, previous ones kept: ${opened//$'\n'/ }"
    return 0
  fi
  sleep $((DELAY * 2))
  for screen in map list detail fuels; do
    launch "$udid" list -demoCarPlay "$screen"
    sleep 3
    if ! opened=$(python3 scripts/carplay.py tap "$udid" "build/carplay-debug/$screen-home.png" 2>&1); then
      echo "::warning title=CarPlay screenshots::could not open Carburants on the CarPlay screen, previous ones kept: ${opened//$'\n'/ }"
      return 0
    fi
    echo "$opened" | tee "build/carplay-debug/$screen.txt"
    sleep $((n == 1 ? DELAY * 2 : DELAY))
    # The whole Mac screen, to see where the click went.
    screencapture -x "build/carplay-debug/$screen-mac.png" 2>/dev/null || true
    xcrun simctl io "$udid" screenshot --display=external --type=png "$(printf '%s/%02d-%s.png' "$tmp" "$n" "$screen")" >/dev/null
    n=$((n + 1))
  done
  rm -rf "$dir"
  mv "$tmp" "$dir"
  ls "$dir"/*.png
}

# ONLY="iphone ipad duo carplay" (any of them, or build) takes just those; all by default.
only="${ONLY:-iphone ipad duo carplay}"
for part in ${only//,/ }; do
  case "$part" in
    build) exit 0 ;;
    iphone) shoot "$IPHONE" iphone-6.9 list:light detail:light fuels:light list:dark detail:dark ;;
    ipad) shoot "$IPAD" ipad-13 list:light detail:light list:dark ;;
    duo) shoot_duo ;;
    carplay) shoot_carplay ;;
    *) echo "Unknown ONLY part: $part" >&2; exit 2 ;;
  esac
done

python3 scripts/screenshots_post.py "$OUT" screenshots
