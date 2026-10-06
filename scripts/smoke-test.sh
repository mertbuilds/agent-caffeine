#!/usr/bin/env bash
# Starts the real app for a few seconds and fails when it does not run: a
# main thread that hangs, a busy loop, no icon in the menu bar, an engine
# that takes no sample. The unit tests never start the app, so they pass on
# a build that hangs at launch.
#
#   scripts/smoke-test.sh                 build Debug, then test that build
#   scripts/smoke-test.sh --app <path>    test a bundle that is built already
#   scripts/smoke-test.sh --seconds <n>   how long the app runs (default 8)
#
# The app runs as `caffeinagent --smoke-test <seconds>` (see
# Caffeinagent/SmokeTest.swift). In that mode it takes no power assertion,
# never reaches the helper, the Keychain, Polar or Sparkle, sends no
# notification and keeps its settings under a bundle identifier of its own, so
# it is safe next to a copy that is installed and running. A second robot
# shows in the menu bar while it runs, and Preferences opens once behind the
# app in front.
#
# Exit 0 and PASS when the app is healthy. The app prints one line of JSON
# with what it measured.

set -euo pipefail

cd "$(dirname "$0")/.."

APP=""
SECONDS_TO_RUN=8
# The app ends itself, also when its main thread hangs. This is for a
# process that does not even get that far.
HARD_TIMEOUT=30
BUILD_DIR="build/smoke-test"
SETTINGS_DOMAIN="com.caffeinagent.app.smoke-test"

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?--app needs a path}"; shift 2 ;;
    --seconds) SECONDS_TO_RUN="${2:?--seconds needs a number}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

BUILT=0
cleanup() {
  # A copy of the app that stays on disk shows up in Spotlight.
  if [ "$BUILT" = 1 ]; then rm -rf "$BUILD_DIR"; fi
  defaults delete "$SETTINGS_DOMAIN" > /dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$SETTINGS_DOMAIN.plist"
}
trap cleanup EXIT

if [ -z "$APP" ]; then
  echo "==> build Debug for the smoke test"
  BUILT=1
  xcodegen generate > /dev/null
  xcodebuild \
    -project Caffeinagent.xcodeproj \
    -scheme Caffeinagent \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    build
  APP="$BUILD_DIR/Build/Products/Debug/caffeinagent.app"
fi

BINARY="$APP/Contents/MacOS/caffeinagent"
if [ ! -x "$BINARY" ]; then
  echo "error: no app binary at $BINARY" >&2
  exit 2
fi

echo "==> smoke test: $APP for $SECONDS_TO_RUN s"
STATUS=0
OUTPUT=$(perl -e 'alarm shift; exec @ARGV' "$HARD_TIMEOUT" "$BINARY" --smoke-test "$SECONDS_TO_RUN") || STATUS=$?
REPORT=$(grep -E '^\{.*"healthy"' <<< "$OUTPUT" | tail -1 || true)
if [ -n "$REPORT" ]; then
  echo "$REPORT"
else
  echo "    the app printed no report"
fi

if [ "$STATUS" = 0 ] && grep -q '"healthy":true' <<< "$REPORT"; then
  echo "PASS: the app starts and runs"
  exit 0
fi
case "$STATUS" in
  0) echo "FAIL: the app left with 0 and gave no healthy report" >&2 ;;
  1) echo "FAIL: the app runs but is not healthy" >&2 ;;
  3) echo "FAIL: the main thread of the app hangs" >&2 ;;
  142) echo "FAIL: the app did not end within $HARD_TIMEOUT s" >&2 ;;
  *) echo "FAIL: the app left with status $STATUS" >&2 ;;
esac
exit 1
