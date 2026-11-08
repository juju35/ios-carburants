#!/usr/bin/env bash
# All of ios-carburants' screenshots on this Mac: iPhone 6.9", iPad 13", iPhone Duo (closed, open, half folded) and
# CarPlay, then optionally a pull request with them. Prepares what scripts/screenshots.sh needs and runs it.
#
#   scripts/screenshots-local.sh               # everything
#   ONLY="iphone ipad" scripts/screenshots-local.sh
#   scripts/screenshots-local.sh --pr          # and open a pull request with the new screenshots
#
# Needs: Xcode 27.1 selected (xcode-select), Homebrew. CarPlay also needs Xcode 26 installed next to it (its Simulator
# app is the only one with the CarPlay screen: xcodes install 26.0.1) and Accessibility for this terminal
# (System Settings › Privacy & Security › Accessibility), as scripts/carplay.py clicks the CarPlay window.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

ONLY="${ONLY:-iphone ipad duo carplay}"
PR=false
[ "${1:-}" = "--pr" ] && PR=true
DUOCTL_SHA=efd5e3d62fd85f555057b429deafcc9c81123454   # same pinned commit as the Screenshots workflow
DUOCTL_DIR="$HOME/.cache/duoctl"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31mxx %s\033[0m\n' "$*" >&2; exit 1; }
has() { [[ " $ONLY " == *" $1 "* ]]; }

[ "$(uname)" = Darwin ] || die "macOS only"

# Xcode: 27.x builds the app (iOS 27.1 SDK, the iPhone Duo's).
say "Xcode"
xcodebuild -version | head -1
sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
[ "${sdk%%.*}" -ge 27 ] || die "iOS SDK $sdk: select Xcode 27.1 (sudo xcode-select -s /Applications/Xcode.app)"

# Tools.
say "Tools"
command -v xcodegen >/dev/null || brew install xcodegen
if ! python3 -c 'import PIL, numpy' 2>/dev/null; then
  python3 -m pip install --user pillow numpy 2>/dev/null \
    || python3 -m pip install --user --break-system-packages pillow numpy
fi

# iOS runtime no older than the deployment target.
min=$(sed -n 's/^ *iOS: "\([0-9.]*\)"/\1/p' project.yml | head -1)
say "iOS runtime $min or later"
have_runtime() {
  xcrun simctl list runtimes -j | python3 -c '
import json, re, sys
need = tuple(int(n) for n in sys.argv[1].split(".")[:2])
for r in json.load(sys.stdin)["runtimes"]:
    m = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", r["identifier"])
    if m and r.get("isAvailable") and tuple(map(int, m.groups())) >= need:
        sys.exit(0)
sys.exit(1)' "$min"
}
have_runtime || xcodebuild -downloadPlatform iOS
have_runtime || die "no iOS $min runtime after the download"
xcrun simctl list runtimes | grep iOS

# duoctl folds the iPhone Duo simulator.
if has duo; then
  say "duoctl ($DUOCTL_SHA)"
  [ -d "$DUOCTL_DIR/.git" ] || git clone -q https://github.com/skarol/duoctl "$DUOCTL_DIR"
  git -C "$DUOCTL_DIR" fetch -q origin "$DUOCTL_SHA" 2>/dev/null || true
  git -C "$DUOCTL_DIR" checkout -q "$DUOCTL_SHA"
  export PATH="$DUOCTL_DIR/skills/duoctl/scripts:$PATH"
  command -v duoctl >/dev/null || die "duoctl not found in $DUOCTL_DIR"
fi

# CarPlay: Xcode 26's Simulator app, and Accessibility for the clicks.
if has carplay; then
  say "CarPlay"
  sim="${CARPLAY_SIMULATOR:-$(ls -d /Applications/Xcode*26*.app/Contents/Developer/Applications/Simulator.app 2>/dev/null | tail -1 || true)}"
  if [ -z "$sim" ] || [ ! -d "$sim" ]; then
    warn "no Xcode 26 Simulator app: CarPlay skipped (xcodes install 26.0.1 --path /Applications/Xcode-26.0.1.app)"
    ONLY="${ONLY//carplay/}"
  elif ! osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
    warn "no Accessibility for this terminal: CarPlay skipped (System Settings › Privacy & Security › Accessibility)"
    ONLY="${ONLY//carplay/}"
  else
    export CARPLAY_SIMULATOR="$sim"
    echo "$sim"
  fi
fi

ONLY=$(echo $ONLY)   # squeeze spaces
[ -n "$ONLY" ] || die "nothing left to take"

# The screenshots: fresh simulators, demo mode, French, 9:41.
say "Screenshots: $ONLY"
xcodegen --quiet
ONLY="$ONLY" scripts/screenshots.sh

say "Changed"
git status --short appstore/screenshots screenshots
if git diff --quiet -- appstore/screenshots screenshots && [ -z "$(git ls-files --others --exclude-standard appstore/screenshots screenshots)" ]; then
  echo "No screenshot changed."
  exit 0
fi

# main is protected: a branch and a pull request.
if $PR; then
  say "Pull request"
  branch="chore/screenshots-$(date +%Y%m%d-%H%M)"
  git switch -c "$branch"
  git add appstore/screenshots screenshots
  git commit -q -m "Update screenshots ($ONLY)"
  git push -q -u origin "$branch"
  gh pr create --fill
fi
