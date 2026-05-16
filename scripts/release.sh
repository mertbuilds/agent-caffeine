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
#          --team-id "5TC37Z26XP" \
#          --password "<app-specific-password>"
#      Generate the app-specific password at appleid.apple.com → Sign-in
#      & Security → App-Specific Passwords.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Caffeinagent"
CONFIG="Release"
TEAM_ID="5TC37Z26XP"
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
  -derivedDataPath "$BUILD_DIR" \
  -quiet \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Developer ID Application"

APP="$BUILD_DIR/Build/Products/$CONFIG/$PROJECT.app"

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "==> zip for notarization"
SUBMIT_ZIP="$BUILD_DIR/$PROJECT-submit.zip"
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
RELEASE_ZIP="$BUILD_DIR/$PROJECT-$VERSION-$BUILD.zip"

echo "==> create release zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"

echo ""
echo "✓ release ready: $RELEASE_ZIP"
echo ""
echo "  signed by: $(codesign -dvv "$APP" 2>&1 | grep 'Authority=' | head -1)"
echo "  notarized: $(xcrun stapler validate "$APP" 2>&1 | tail -1)"
echo "  gatekeeper: $(spctl -a -t exec -vvv "$APP" 2>&1 | tail -1)"
