#!/usr/bin/env bash
# Release build → sign → notarize → staple → zip.
#
# One-time setup before first run:
#   1. In Xcode → Settings → Accounts → your account → Manage Certificates,
#      click + → "Developer ID Application". This installs the cert in your
#      login keychain so xcodebuild can find it.
#   2. Store notarization credentials once via:
#        xcrun notarytool store-credentials caffeinagent-notary \
#          --apple-id "<your-apple-id-email>" \
#          --team-id "3HGP3W3TLD" \
#          --password "<app-specific-password>"
#      Generate the app-specific password at appleid.apple.com → Sign-in
#      & Security → App-Specific Passwords.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Caffeinagent"
CONFIG="Release"
TEAM_ID="3HGP3W3TLD"
NOTARY_PROFILE="caffeinagent-notary"
BUILD_DIR="build/release"

# Regenerate project.pbxproj from project.yml so any config drift is reset.
xcodegen generate > /dev/null

echo "==> clean build"
rm -rf "$BUILD_DIR"

echo "==> xcodebuild ($CONFIG)"
xcodebuild \
  -project "${PROJECT}.xcodeproj" \
  -scheme "${PROJECT}" \
  -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  -quiet \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

APP="$BUILD_DIR/Build/Products/$CONFIG/caffeinagent.app"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "==> zip for notarization"
SUBMIT_ZIP="$BUILD_DIR/caffeinagent-submit.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

echo "==> submit to apple notary service (waits up to 30 min)"
xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> staple notarization ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
RELEASE_ZIP="$BUILD_DIR/agent-caffeine-$VERSION-$BUILD.zip"

echo "==> create release zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"

# PRODUCT_NAME stays "caffeinagent" so the binary path + bundle id are
# stable for signing/updates, but the user-facing bundle inside the dmg
# needs to read "agent caffeine.app". Copy preserves the stapled ticket
# and code signature (bundle name isn't part of either).
DIST_APP="$BUILD_DIR/Build/Products/$CONFIG/agent caffeine.app"
rm -rf "$DIST_APP"
cp -R "$APP" "$DIST_APP"

echo "==> build dmg (drag-to-applications)"
# dmgbuild writes the .DS_Store directly (no Finder/AppleScript dance), so
# the layout + background survive even when the build host hasn't granted
# Automation permissions to whatever process is calling this script.
RELEASE_DMG="$BUILD_DIR/agent-caffeine-$VERSION-$BUILD.dmg"
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || ls "$HOME"/Library/Python/*/bin/dmgbuild 2>/dev/null | sort -V | tail -1 || true)}"
[ -x "$DMGBUILD" ] || { echo "error: dmgbuild not found" >&2; exit 1; }
rm -f "$RELEASE_DMG"
DMG_APP_PATH="$(pwd)/$DIST_APP" \
DMG_BACKGROUND="$(pwd)/scripts/dmg-background.png" \
  "$DMGBUILD" \
  -s scripts/dmg-settings.py \
  "agent caffeine" \
  "$RELEASE_DMG"

echo "==> sign dmg"
codesign --sign "Developer ID Application: Mert Duzgun (${TEAM_ID})" --timestamp "$RELEASE_DMG"

echo "==> notarize dmg"
xcrun notarytool submit "$RELEASE_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> staple dmg"
xcrun stapler staple "$RELEASE_DMG"
xcrun stapler validate "$RELEASE_DMG"

# Publish the notarized dmg to the Polar "File Downloads" benefit (add new +
# archive old). Credentials come from the standard per-service env file
# (~/.config/polar/credentials.env: POLAR_ACCESS_TOKEN + POLAR_BENEFIT_ID),
# unless already exported. Opt-in: skips cleanly if the file/vars are absent.
POLAR_ENV="$HOME/.config/polar/credentials.env"
if [ -f "$POLAR_ENV" ]; then set -a; . "$POLAR_ENV"; set +a; fi
if [ -n "${POLAR_ACCESS_TOKEN:-}" ] && [ -n "${POLAR_BENEFIT_ID:-}" ]; then
  echo "==> publish dmg to Polar (add new + disable old)"
  node scripts/polar-publish.mjs "$RELEASE_DMG"
else
  echo "==> skip Polar publish (no creds at $POLAR_ENV and env vars unset)"
fi

echo ""
echo "✓ release artifacts:"
echo "  zip: $RELEASE_ZIP"
echo "  dmg: $RELEASE_DMG"
echo ""
echo "  signed by: $(codesign -dvv "$APP" 2>&1 | grep 'Authority=' | head -1)"
echo "  notarized app: $(xcrun stapler validate "$APP" 2>&1 | tail -1)"
echo "  notarized dmg: $(xcrun stapler validate "$RELEASE_DMG" 2>&1 | tail -1)"
echo "  gatekeeper: $(spctl -a -t exec -vvv "$APP" 2>&1 | tail -1)"
