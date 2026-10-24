#!/usr/bin/env bash
# App Store screenshots (iPhone 6.9" and iPad 13", the two sizes App Store Connect requires) and the README's
# smaller copies, from the app's demo mode (sample stations around Rennes) on fresh simulators.
#
#   scripts/screenshots.sh
#   IPHONE="iPhone 17 Pro Max" IPAD="iPad Pro 13-inch (M4)" scripts/screenshots.sh   # other device types
#
# Needs Xcode, XcodeGen and Python 3 with Pillow (pip install pillow). The Screenshots workflow runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

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
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array fr-FR
  xcrun simctl spawn "$udid" defaults write -g AppleLocale fr_FR
  xcrun simctl shutdown "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$udid" "$app"
  rm -rf "$dir"
  mkdir -p "$dir"

  local n=1 shot screen appearance file
  for shot in "$@"; do
    screen="${shot%%:*}"
    appearance="${shot##*:}"
    xcrun simctl ui "$udid" appearance "$appearance"
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BUNDLE" -demo YES -demoScreen "$screen" \
      -AppleLanguages '(fr)' -AppleLocale fr_FR >/dev/null
    # Map tiles come from Apple's servers: the first launch takes longer.
    sleep $((n == 1 ? DELAY * 2 : DELAY))
    file=$(printf '%s/%02d-%s-%s.png' "$dir" "$n" "$screen" "$appearance")
    xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null
    echo "$file"
    n=$((n + 1))
  done
}

shoot "$IPHONE" iphone-6.9 list:light detail:light fuels:light list:dark detail:dark
shoot "$IPAD" ipad-13 list:light detail:light list:dark

python3 scripts/screenshots_post.py "$OUT" screenshots
