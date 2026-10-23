#!/usr/bin/env bash
# Release build → sign → notarize → staple → zip → dmg → appcast → R2.
#
# This script is the only way to publish a release. The dmg, the appcast
# Sparkle reads and the latest.json the download page reads go to the R2
# private bucket named by R2_BUCKET in ~/.config/agent-caffeine/release.env,
# under mac/, and the site's Worker serves the files at
# https://caffeinagent.com/mac/<file> (site/apps/web/src/lib/mac-files.ts). The
# dmg goes up first, so a feed never points at a file that is not there yet. An
# upload is live at once: there is no site deploy in between.
#
# Every check of a file that may not be uploaded yet asks the bucket first, and
# the site only when the bucket cannot be read. The checks after the upload read
# the site, since that is what the app and the browsers ask.
#
# Sparkle offers an update only when its build number is above every one in the
# published appcast, so the script stops before it builds when
# CURRENT_PROJECT_VERSION in project.yml is not. The dmg is stored as
# agent-caffeine-<version>-<build>.dmg and the script stops when the bucket
# already holds that name. /download redirects to it, and the Worker serves it
# with a Content-Disposition that saves it as agent-caffeine-<version>.dmg, the
# `filename` that latest.json names too.
#
# Run it from a local Terminal on the Mac. Sparkle signs with the private key in
# the login keychain, and the keychain refuses SSH and scripted sessions.
# GitHub Actions runs it too (.github/workflows/mac-release.yml), with the keys
# in the environment: see the end of this header.
#
#   --dry-run  do everything local (build, sign, smoke test, dmg, appcast,
#              latest.json) but notarize nothing and upload nothing, and print
#              each upload command instead.
#   --allow-dirty  only with --dry-run: build from a working tree with changes
#              that are not committed. A release is always built from a clean
#              tree, so what ships is what a commit holds.
#   --notarize  only with --dry-run: notarize and staple the app and the dmg
#              all the same, and still upload nothing. The workflow's dry run
#              uses it.
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
#   3. The Sparkle EdDSA private key is in the login keychain under the account
#      agent-caffeine, with a backup in ~/.config/agent-caffeine/
#      sparkle-ed25519.key (mode 600). Its public half is SUPublicEDKey in
#      project.yml. Every Sparkle tool call here passes --account agent-caffeine,
#      never Sparkle's default account, which holds another product's key.
#      Without the key no shipped copy of the app accepts an update.
#   4. `cf auth login` with the Cloudflare account that holds the bucket, or the
#      S3 key pair below in release.env. cf is Cloudflare's cf cli.
#   5. Put the bucket name in ~/.config/agent-caffeine/release.env (mode 600),
#      as R2_BUCKET=<bucket>.
#
# The runner has none of that setup, so the workflow sets these instead. With
# none of them set the script runs as it always has:
#   NOTARY_API_KEY_FILE, NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
#                         an App Store Connect API key (.p8 file), its id and
#                         its issuer. With all three set, notarytool uses them
#                         in place of the keychain profile.
#   SPARKLE_ED_KEY_FILE   the Sparkle private key as a file, in place of the
#                         login keychain.
#   R2_BUCKET             the bucket, when release.env is not there.
#   R2_S3_ACCESS_KEY_ID, R2_S3_SECRET_ACCESS_KEY, R2_S3_ENDPOINT
#                         the S3 key pair of an R2 API token for the bucket and
#                         https://<account id>.r2.cloudflarestorage.com. With
#                         all three set, curl makes every bucket call with
#                         --aws-sigv4 and cf is not needed.
#   SMOKE_TIMING=warn     the smoke test prints its timing problems as warnings
#                         and fails only on a part that does not work. See
#                         scripts/smoke-test.sh.
# On the Mac, release.env can hold any of these too, so a local release needs
# neither the cf login nor the keychain items. The script reads release.env
# before it picks a mode, and a variable set in the environment wins over the
# same one in the file.
# The Developer ID certificate is found the same way in both: the workflow puts
# it in a keychain of its own and makes that the default keychain.

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Caffeinagent"
CONFIG="Release"
TEAM_ID="3HGP3W3TLD"
NOTARY_PROFILE="caffeinagent-notary"
RELEASE_ENV="$HOME/.config/agent-caffeine/release.env"
SITE_URL="https://caffeinagent.com/mac"
SPARKLE_ACCOUNT="agent-caffeine"
KEY_PLACEHOLDER="REPLACE_WITH_AGENT_CAFFEINE_SPARKLE_PUBLIC_KEY"
BUILD_DIR="build/release"
SITE_DIR="$BUILD_DIR/site"

DRY_RUN=0
ALLOW_DIRTY=0
NOTARIZE_DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --notarize) NOTARIZE_DRY_RUN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [ "$ALLOW_DIRTY" = 1 ] && [ "$DRY_RUN" = 0 ]; then
  echo "error: --allow-dirty is only for --dry-run. a release is built from a" >&2
  echo "       clean working tree." >&2
  exit 2
fi
if [ "$NOTARIZE_DRY_RUN" = 1 ] && [ "$DRY_RUN" = 0 ]; then
  echo "error: --notarize is only for --dry-run. a release always notarizes." >&2
  exit 2
fi
NOTARIZE=1
if [ "$DRY_RUN" = 1 ] && [ "$NOTARIZE_DRY_RUN" = 0 ]; then
  NOTARIZE=0
fi

# Read before any of the modes below is picked. A variable already in the
# environment keeps its value: the file only fills in the ones that are unset.
if [ -f "$RELEASE_ENV" ]; then
  ENV_BEFORE=$(export -p)
  . "$RELEASE_ENV"
  eval "$ENV_BEFORE"
  unset ENV_BEFORE
fi

# All three, or none and the keychain profile.
if [ -n "${NOTARY_API_KEY_FILE:-}${NOTARY_API_KEY_ID:-}${NOTARY_API_ISSUER_ID:-}" ]; then
  if [ -z "${NOTARY_API_KEY_FILE:-}" ] || [ -z "${NOTARY_API_KEY_ID:-}" ] || [ -z "${NOTARY_API_ISSUER_ID:-}" ]; then
    echo "error: set all three of NOTARY_API_KEY_FILE, NOTARY_API_KEY_ID and" >&2
    echo "       NOTARY_API_ISSUER_ID, or none of them." >&2
    exit 2
  fi
  if [ ! -s "$NOTARY_API_KEY_FILE" ]; then
    echo "error: NOTARY_API_KEY_FILE names no file with a key in it." >&2
    exit 2
  fi
fi
notary_submit() {
  if [ -n "${NOTARY_API_KEY_FILE:-}" ]; then
    xcrun notarytool submit "$1" \
      --key "$NOTARY_API_KEY_FILE" \
      --key-id "$NOTARY_API_KEY_ID" \
      --issuer "$NOTARY_API_ISSUER_ID" \
      --wait
  else
    xcrun notarytool submit "$1" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  fi
}

if [ -n "${SPARKLE_ED_KEY_FILE:-}" ] && [ ! -s "$SPARKLE_ED_KEY_FILE" ]; then
  echo "error: SPARKLE_ED_KEY_FILE names no file with a key in it." >&2
  exit 2
fi
# The key file when there is one, else the key in the login keychain under
# SPARKLE_ACCOUNT, never Sparkle's default account.
sparkle_tool() {
  tool="$1"
  shift
  if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
    "$SPARKLE_BIN/$tool" --ed-key-file "$SPARKLE_ED_KEY_FILE" "$@"
  else
    "$SPARKLE_BIN/$tool" --account "$SPARKLE_ACCOUNT" "$@"
  fi
}

# The bucket is reached through cf, or through its S3 endpoint when the key pair
# is in the environment. r2_get and r2_put below are the only two callers.
R2_TRANSPORT=cf
if [ -n "${R2_S3_ACCESS_KEY_ID:-}${R2_S3_SECRET_ACCESS_KEY:-}${R2_S3_ENDPOINT:-}" ]; then
  if [ -z "${R2_S3_ACCESS_KEY_ID:-}" ] || [ -z "${R2_S3_SECRET_ACCESS_KEY:-}" ] || [ -z "${R2_S3_ENDPOINT:-}" ]; then
    echo "error: set all three of R2_S3_ACCESS_KEY_ID, R2_S3_SECRET_ACCESS_KEY and" >&2
    echo "       R2_S3_ENDPOINT, or none of them." >&2
    exit 2
  fi
  # The key pair signs requests to this host, so it is R2's own or nothing.
  if ! [[ "$R2_S3_ENDPOINT" =~ ^https://[0-9a-f]{32}(\.(eu|fedramp))?\.r2\.cloudflarestorage\.com$ ]]; then
    echo "error: R2_S3_ENDPOINT is not https://<account id>.r2.cloudflarestorage.com" >&2
    echo "       (or its .eu or .fedramp form)." >&2
    exit 2
  fi
  R2_TRANSPORT=s3
  # What the bucket answered, kept to show the reason when a request fails.
  S3_BODY=$(mktemp)
  trap 'rm -f "$S3_BODY"' EXIT
fi
echo "==> bucket access: $R2_TRANSPORT"

# One signed request to the S3 endpoint. It prints the http status and nothing
# else. The key pair goes to curl as a config on stdin, so it is in no argument
# list and no log. curl signs again on every retry, and a 4xx is never tried
# again.
s3_curl() {
  printf 'user = "%s:%s"\n' "$R2_S3_ACCESS_KEY_ID" "$R2_S3_SECRET_ACCESS_KEY" \
    | curl -sS -K - --proto '=https' --aws-sigv4 "aws:amz:auto:s3" \
      --connect-timeout 20 --retry 3 --retry-all-errors -w '%{http_code}' "$@"
}

# The first 500 bytes of the bucket's answer, which name the reason.
s3_reason() {
  if [ -s "$1" ]; then
    head -c 500 "$1" >&2
    echo >&2
  fi
}

# Writes the object to a file. Returns 1 when it could not be read: through cf
# that is any failure, through S3 only a 404, and any other answer stops the
# script.
r2_get() {
  key="$1"
  file="$2"
  if [ "$R2_TRANSPORT" = cf ]; then
    command -v cf > /dev/null 2>&1 || return 1
    cf r2 objects get "$key" --bucket-name "$R2_BUCKET" > "$file" 2> /dev/null
    return
  fi
  body="$file"
  if [ "$file" = /dev/null ]; then
    body="$S3_BODY"
  fi
  : > "$body"
  STATUS=$(s3_curl -o "$body" "$R2_S3_ENDPOINT/$R2_BUCKET/$key") || STATUS="no response"
  case "$STATUS" in
    200) return 0 ;;
    404) return 1 ;;
    *)
      echo "error: could not read $key from the bucket over S3 ($STATUS)." >&2
      s3_reason "$body"
      exit 1
      ;;
  esac
}

# What ships has to be what a commit holds. Untracked files count: the build
# takes every source file in the folders, tracked or not.
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ] && [ "$ALLOW_DIRTY" = 0 ]; then
  echo "error: the working tree has changes that are not committed:" >&2
  printf '%s\n' "$DIRTY" | head -20 >&2
  echo "       commit or stash them, or run with --dry-run --allow-dirty." >&2
  exit 1
fi

read_key() {
  { grep -E "^ *$1: " project.yml || true; } | head -1 | sed -E "s/^ *$1: *[\"']?([^\"']*)[\"']?.*$/\1/"
}

# A build without the real public key can never be updated again, so a bad
# merge that loses it must not ship.
PUBLIC_KEY=$(read_key SUPublicEDKey)
if [ -z "$PUBLIC_KEY" ] || [ "$PUBLIC_KEY" = "$KEY_PLACEHOLDER" ]; then
  echo "error: SUPublicEDKey in project.yml is missing or still the placeholder." >&2
  echo "       the key pair is in the login keychain under the account" >&2
  echo "       $SPARKLE_ACCOUNT. print its public half from a local Terminal with:" >&2
  echo "         xcodegen generate" >&2
  echo "         xcodebuild -resolvePackageDependencies -project $PROJECT.xcodeproj \\" >&2
  echo "           -scheme $PROJECT -derivedDataPath build/tools" >&2
  echo "         build/tools/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account $SPARKLE_ACCOUNT" >&2
  echo "       and paste the printed key into project.yml as SUPublicEDKey." >&2
  exit 1
fi

if [ "$DRY_RUN" = 0 ] && [ -z "${R2_BUCKET:-}" ]; then
  echo "error: R2_BUCKET is not set. Put the bucket the site serves /mac/ from" >&2
  echo "       in $RELEASE_ENV (mode 600):" >&2
  echo "         R2_BUCKET=<bucket>" >&2
  exit 1
fi
if [ "$R2_TRANSPORT" = s3 ] && [ -z "${R2_BUCKET:-}" ]; then
  echo "error: R2_BUCKET is not set, so the S3 key pair has no bucket to reach." >&2
  exit 1
fi

# The key pair has to read the bucket before anything is built or notarized.
if [ "$DRY_RUN" = 0 ] && [ "$R2_TRANSPORT" = s3 ]; then
  echo "==> check that the S3 key pair reaches the bucket"
  if ! r2_get mac/latest.json /dev/null; then
    echo "error: the bucket has no mac/latest.json (404 over S3), so the release" >&2
    echo "       was not started. check R2_S3_ENDPOINT and R2_BUCKET." >&2
    exit 1
  fi
fi

if [ "$DRY_RUN" = 0 ] && [ "$R2_TRANSPORT" = cf ]; then
  if ! command -v cf > /dev/null 2>&1; then
    echo "error: Cloudflare's cf cli is not installed, so the release cannot be" >&2
    echo "       uploaded. install it, or run this script with --dry-run." >&2
    exit 1
  fi
  # whoami exits 0 when nobody is logged in, so its answer is what is checked.
  echo "==> cloudflare login"
  WHOAMI=$(cf auth whoami 2>&1) || true
  if ! grep -q '"authenticated": true' <<< "$WHOAMI" || grep -q '"tokenValid": false' <<< "$WHOAMI"; then
    printf '%s\n' "$WHOAMI" >&2
    echo "error: cf is not logged in, so the release cannot reach the bucket." >&2
    echo "       run cf auth login, or run this script with --dry-run." >&2
    exit 1
  fi
  grep -E '"(authSource|email)":' <<< "$WHOAMI" || true
fi

# Regenerate project.pbxproj from project.yml so any config drift is reset.
xcodegen generate > /dev/null

echo "==> clean build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# The published appcast is the input, so older versions keep their entry in the
# feed instead of being dropped on every release. The bucket is read first,
# since it is what the site serves; the site is the fallback for a bucket this
# login cannot read or that holds no feed yet. Only a 404 there starts a
# new feed: any other failure stops the release rather than lose the history.
echo "==> fetch the published appcast"
PUBLISHED_APPCAST="$BUILD_DIR/appcast.published.xml"
if [ -n "${R2_BUCKET:-}" ] \
  && r2_get mac/appcast.xml "$PUBLISHED_APPCAST" \
  && [ -s "$PUBLISHED_APPCAST" ]; then
  echo "    from the bucket: mac/appcast.xml"
else
  STATUS=$(curl -sS -o "$PUBLISHED_APPCAST" -w '%{http_code}' "$SITE_URL/appcast.xml") || STATUS="no response"
  case "$STATUS" in
    200) echo "    from $SITE_URL/appcast.xml" ;;
    404)
      rm -f "$PUBLISHED_APPCAST"
      echo "    none published yet, the feed starts with this release"
      ;;
    *)
      echo "error: could not read $SITE_URL/appcast.xml ($STATUS)." >&2
      echo "       without it every older version would drop out of the feed." >&2
      exit 1
      ;;
  esac
fi
PUBLISHED_BUILD=0
if [ -f "$PUBLISHED_APPCAST" ]; then
  if ! grep -q '<rss' "$PUBLISHED_APPCAST"; then
    echo "error: the published appcast is not an rss feed: $PUBLISHED_APPCAST" >&2
    exit 1
  fi
  PUBLISHED_BUILD=$(grep -oE '<sparkle:version>[0-9]+</sparkle:version>' "$PUBLISHED_APPCAST" \
    | grep -oE '[0-9]+' | sort -n | tail -1 || true)
  PUBLISHED_BUILD="${PUBLISHED_BUILD:-0}"
fi
echo "    highest published build: $PUBLISHED_BUILD"

dmg_name() {
  echo "agent-caffeine-$1-$2.dmg"
}

# The version alone, as `filename` in latest.json. It is also the name on disk:
# the Worker serves a dmg with a Content-Disposition that drops the build
# number. The build number in the stored name keeps every url new.
download_name() {
  echo "agent-caffeine-$1.dmg"
}

# The last build that was sold before the feed existed. The feed does not
# list it, so a new release is above it whatever the feed says.
LAST_BUILD_BEFORE_FEED=13

# Sparkle compares CFBundleVersion, so an item whose build number is not above
# every published one is never offered. A dmg name the bucket has held once is
# never uploaded again.
check_new_release() {
  version="$1"
  build="$2"
  if ! printf '%s' "$build" | grep -qE '^[0-9]+$'; then
    echo "error: build number '$build' is not a whole number" >&2
    exit 1
  fi
  if [ "$build" -le "$LAST_BUILD_BEFORE_FEED" ]; then
    echo "error: build $build is not above build $LAST_BUILD_BEFORE_FEED, which buyers" >&2
    echo "       already run, so Sparkle would never offer it. raise" >&2
    echo "       CURRENT_PROJECT_VERSION in project.yml." >&2
    exit 1
  fi
  if [ "$build" -le "$PUBLISHED_BUILD" ]; then
    echo "error: build $build is not above build $PUBLISHED_BUILD in the published" >&2
    echo "       appcast, so Sparkle would never offer it. raise" >&2
    echo "       CURRENT_PROJECT_VERSION in project.yml." >&2
    exit 1
  fi
  name=$(dmg_name "$version" "$build")
  # Over S3 r2_get fails only on a 404, so its answer is final. Through cf a
  # failure may be a login that cannot read the bucket, so the site is asked too.
  held=0
  if [ "$R2_TRANSPORT" = s3 ]; then
    if r2_get "mac/$name" /dev/null; then
      held=1
    fi
  elif { [ -n "${R2_BUCKET:-}" ] && r2_get "mac/$name" /dev/null; } \
    || curl -sfI "$SITE_URL/$name" > /dev/null; then
    held=1
  fi
  if [ "$held" = 1 ]; then
    echo "error: the bucket already holds mac/$name" >&2
    echo "       raise CURRENT_PROJECT_VERSION in project.yml." >&2
    exit 1
  fi
}

echo "==> check the build number"
check_new_release "$(read_key MARKETING_VERSION)" "$(read_key CURRENT_PROJECT_VERSION)"

# Not in a dry run: the build loop asks for one after every change, and the
# tests run there by themselves.
if [ "$DRY_RUN" = 1 ]; then
  echo "==> skip the unit tests (--dry-run)"
else
  echo "==> unit tests"
  TESTS_DIR="$BUILD_DIR-tests"
  rm -rf "$TESTS_DIR"
  xcodebuild test \
    -project "${PROJECT}.xcodeproj" \
    -scheme "${PROJECT}" \
    -destination "platform=macOS" \
    -derivedDataPath "$TESTS_DIR" \
    -quiet
  rm -rf "$TESTS_DIR"
fi

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

# Sparkle's command line tools come down with the Swift package, so they always
# match the framework inside the app.
SPARKLE_BIN="$BUILD_DIR/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$SPARKLE_BIN/sign_update" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "error: Sparkle tools are missing from $SPARKLE_BIN" >&2
  exit 1
fi

echo "==> verify signature"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

# The root helper. Xcode signs it in its own target, signs it again when it
# copies it into Contents/MacOS, and seals the app last, so the bundle is
# signed inside out. The app and the helper each accept only the other when it
# meets the requirement in Caffeinagent/Power/SleepFlagHelperProtocol.swift, so
# a release that fails it could never turn the sleep override on.
echo "==> verify the helper"
HELPER_ID="com.caffeinagent.app.helper"
HELPER="$APP/Contents/MacOS/CaffeinagentHelper"
HELPER_PLIST="$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist"
signed_by_team() {
  echo "anchor apple generic and identifier \"$1\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM_ID\""
}
if [ ! -x "$HELPER" ] || [ ! -f "$HELPER_PLIST" ]; then
  echo "error: the helper or its launchd plist is missing from the app:" >&2
  echo "         $HELPER" >&2
  echo "         $HELPER_PLIST" >&2
  exit 1
fi
/usr/bin/plutil -lint "$HELPER_PLIST" > /dev/null
BUNDLE_PROGRAM=$(/usr/libexec/PlistBuddy -c "Print :BundleProgram" "$HELPER_PLIST")
if [ "$APP/$BUNDLE_PROGRAM" != "$HELPER" ]; then
  echo "error: BundleProgram in $HELPER_PLIST is $BUNDLE_PROGRAM, not the helper's path." >&2
  exit 1
fi
codesign --verify --strict -R="$(signed_by_team "$HELPER_ID")" "$HELPER"
codesign --verify --strict -R="$(signed_by_team "com.caffeinagent.app")" "$APP"
HELPER_SIGNATURE=$(codesign -dv "$HELPER" 2>&1)
if ! grep -qE '^CodeDirectory .*flags=[^ ]*runtime' <<< "$HELPER_SIGNATURE"; then
  echo "error: the helper is not signed with the hardened runtime, so the notary" >&2
  echo "       service would refuse the app." >&2
  exit 1
fi
# An entitlement on a root daemon without a provisioning profile makes macOS
# refuse to start it.
if codesign -d --entitlements - --xml "$HELPER" 2> /dev/null | grep -q '<key>'; then
  echo "error: the helper carries entitlements:" >&2
  codesign -d --entitlements - "$HELPER" >&2
  exit 1
fi
HELPER_ARCHS=$(/usr/bin/lipo -archs "$HELPER")
case " $HELPER_ARCHS " in
  *" arm64 "*) ;;
  *) echo "error: the helper has no arm64 slice: $HELPER_ARCHS" >&2; exit 1 ;;
esac
case " $HELPER_ARCHS " in
  *" x86_64 "*) ;;
  *) echo "error: the helper has no x86_64 slice: $HELPER_ARCHS" >&2; exit 1 ;;
esac
echo "    $HELPER_ID: $HELPER_ARCHS, hardened runtime, team $TEAM_ID"

# The command the agents' hooks run. The hook entries the app writes point at
# this path, and a hook has to answer with nothing and exit 0.
echo "==> verify the hook command"
HOOK_ID="com.caffeinagent.app.hook"
HOOK="$APP/Contents/MacOS/CaffeinagentHook"
if [ ! -x "$HOOK" ]; then
  echo "error: the hook command is missing from the app: $HOOK" >&2
  exit 1
fi
codesign --verify --strict -R="$(signed_by_team "$HOOK_ID")" "$HOOK"
# Read into a variable first: with pipefail, grep -q closes the pipe at its
# match and codesign then fails the pipeline.
HOOK_SIGNATURE=$(codesign -dv "$HOOK" 2>&1)
if ! grep -qE '^CodeDirectory .*flags=[^ ]*runtime' <<< "$HOOK_SIGNATURE"; then
  echo "error: the hook command is not signed with the hardened runtime." >&2
  exit 1
fi
HOOK_ARCHS=$(/usr/bin/lipo -archs "$HOOK")
for ARCH in arm64 x86_64; do
  case " $HOOK_ARCHS " in
    *" $ARCH "*) ;;
    *) echo "error: the hook command has no $ARCH slice: $HOOK_ARCHS" >&2; exit 1 ;;
  esac
done
HOOK_OUTPUT=$(CAFFEINAGENT_HOOKS_DIR="$(mktemp -d)" "$HOOK" claude Stop < /dev/null 2>&1) || {
  echo "error: the hook command did not exit 0." >&2
  exit 1
}
if [ -n "$HOOK_OUTPUT" ]; then
  echo "error: the hook command printed something: $HOOK_OUTPUT" >&2
  exit 1
fi
echo "    $HOOK_ID: $HOOK_ARCHS, hardened runtime, silent"

# The command line tool, agent-caffeine. Settings shows this path, and people
# link it into a folder on their PATH. It is asked for its status against an
# empty folder, so it never reads the holds of a copy that is installed.
echo "==> verify the command line tool"
CLI_ID="com.caffeinagent.app.cli"
CLI="$APP/Contents/MacOS/agent-caffeine"
if [ ! -x "$CLI" ]; then
  echo "error: the command line tool is missing from the app: $CLI" >&2
  exit 1
fi
codesign --verify --strict -R="$(signed_by_team "$CLI_ID")" "$CLI"
CLI_SIGNATURE=$(codesign -dv "$CLI" 2>&1)
if ! grep -qE '^CodeDirectory .*flags=[^ ]*runtime' <<< "$CLI_SIGNATURE"; then
  echo "error: the command line tool is not signed with the hardened runtime." >&2
  exit 1
fi
CLI_ARCHS=$(/usr/bin/lipo -archs "$CLI")
for ARCH in arm64 x86_64; do
  case " $CLI_ARCHS " in
    *" $ARCH "*) ;;
    *) echo "error: the command line tool has no $ARCH slice: $CLI_ARCHS" >&2; exit 1 ;;
  esac
done
CLI_HOME=$(mktemp -d)
CLI_OUTPUT=$(AGENT_CAFFEINE_HOME="$CLI_HOME" "$CLI" status 2>&1) || {
  echo "error: the command line tool did not exit 0: $CLI_OUTPUT" >&2
  exit 1
}
if ! grep -q '^No holds\.$' <<< "$CLI_OUTPUT"; then
  echo "error: the command line tool gave an answer that was not expected: $CLI_OUTPUT" >&2
  exit 1
fi
# A command below the tool ends as it does alone: with its own exit code, and
# by SIGPIPE (128 + 13) when its reader is gone. The tool ignores that signal
# for itself and has to give it back to the command.
CLI_CODE=0
AGENT_CAFFEINE_HOME="$CLI_HOME" "$CLI" hold -- /bin/sh -c 'exit 7' 2> /dev/null || CLI_CODE=$?
if [ "$CLI_CODE" != 7 ]; then
  echo "error: the command line tool ended with $CLI_CODE for a command that ended with 7." >&2
  exit 1
fi
set +e
AGENT_CAFFEINE_HOME="$CLI_HOME" "$CLI" hold -- /usr/bin/yes 2> /dev/null | head -1 > /dev/null
CLI_CODE=${PIPESTATUS[0]}
set -e
if [ "$CLI_CODE" != 141 ]; then
  echo "error: the command line tool ended with $CLI_CODE for a command whose reader was gone, and not with 141." >&2
  exit 1
fi
echo "    $CLI_ID: $CLI_ARCHS, hardened runtime, answers, runs a command"

# The skill that "Set up for agents" writes into the skills folders of the
# agents. It is in the app, it is the one of the repo, and the tool prints it.
echo "==> verify the bundled skill"
SKILL="$APP/Contents/Resources/skills/agent-caffeine/SKILL.md"
if [ ! -s "$SKILL" ]; then
  echo "error: the skill is missing from the app: $SKILL" >&2
  exit 1
fi
if ! cmp -s "$SKILL" skills/agent-caffeine/SKILL.md; then
  echo "error: the skill in the app is not skills/agent-caffeine/SKILL.md." >&2
  exit 1
fi
if ! AGENT_CAFFEINE_HOME="$CLI_HOME" "$CLI" skill | cmp -s - "$SKILL"; then
  echo "error: agent-caffeine skill does not print the bundled skill." >&2
  exit 1
fi
echo "    skills/agent-caffeine/SKILL.md: in the app, printed by the tool"

# The unit tests never start the app. This starts the signed app for a few
# seconds, next to a copy that is installed, and stops the release when its
# main thread hangs, it burns a core, it shows no icon, it takes no sample or
# its open menu keeps the processor busy.
SMOKE_TIMING="${SMOKE_TIMING:-strict}" scripts/smoke-test.sh --app "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "==> check the built app's build number"
check_new_release "$VERSION" "$BUILD"
DMG_NAME=$(dmg_name "$VERSION" "$BUILD")
DMG_URL="$SITE_URL/$DMG_NAME"

if [ "$NOTARIZE" = 0 ]; then
  echo "==> skip notarization (--dry-run)"
else
  echo "==> zip for notarization"
  SUBMIT_ZIP="$BUILD_DIR/caffeinagent-submit.zip"
  /usr/bin/ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

  echo "==> submit to apple notary service (waits up to 30 min)"
  notary_submit "$SUBMIT_ZIP"

  echo "==> staple notarization ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  # What a Mac asks before it opens the app. A refusal here stops the release
  # before anything is uploaded.
  echo "==> gatekeeper check of the app"
  spctl -a -t exec -vv "$APP"
fi

RELEASE_ZIP="$BUILD_DIR/agent-caffeine-$VERSION-$BUILD.zip"

echo "==> create release zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"

# PRODUCT_NAME stays "caffeinagent" so the binary path + bundle id are
# stable for signing/updates, but the user-facing bundle inside the dmg
# is "Agent Caffeine.app" from 1.0.2 (1.0.0 and 1.0.1: "agent caffeine.app").
# Copy preserves the stapled ticket and code signature (bundle name isn't
# part of either). An update keeps the name of the bundle it replaces, and
# the app supports both names: see AppInstall.swift.
DIST_NAME="Agent Caffeine.app"
DIST_APP="$BUILD_DIR/Build/Products/$CONFIG/$DIST_NAME"
rm -rf "$DIST_APP"
cp -R "$APP" "$DIST_APP"
# The build folder is on a volume that may not tell names apart by case, so
# the name on disk is read back.
if [ "$(cd "$BUILD_DIR/Build/Products/$CONFIG" && ls -d *affeine.app)" != "$DIST_NAME" ]; then
  echo "error: the bundle for the dmg is not named $DIST_NAME" >&2
  exit 1
fi
codesign --verify --deep --strict "$DIST_APP"

echo "==> build dmg (drag-to-applications)"
# dmgbuild writes the .DS_Store directly (no Finder/AppleScript dance), so
# the layout + background survive even when the build host hasn't granted
# Automation permissions to whatever process is calling this script.
# The name after the settings is the name of the volume, which Finder shows as
# the title of the install window. Nothing reads it, so it is the brand.
RELEASE_DMG="$BUILD_DIR/$DMG_NAME"
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || ls "$HOME"/Library/Python/*/bin/dmgbuild 2>/dev/null | sort -V | tail -1 || true)}"
[ -x "$DMGBUILD" ] || { echo "error: dmgbuild not found" >&2; exit 1; }
rm -f "$RELEASE_DMG"
DMG_APP_PATH="$(pwd)/$DIST_APP" \
DMG_BACKGROUND="$(pwd)/scripts/dmg-background.png" \
  "$DMGBUILD" \
  -s scripts/dmg-settings.py \
  "Agent Caffeine" \
  "$RELEASE_DMG"

echo "==> sign dmg"
codesign --sign "Developer ID Application: Mert Duzgun (${TEAM_ID})" --timestamp "$RELEASE_DMG"

if [ "$NOTARIZE" = 1 ]; then
  echo "==> notarize dmg"
  notary_submit "$RELEASE_DMG"

  echo "==> staple dmg"
  xcrun stapler staple "$RELEASE_DMG"
  xcrun stapler validate "$RELEASE_DMG"

  echo "==> gatekeeper check of the dmg"
  spctl -a -t open --context context:primary-signature -vv "$RELEASE_DMG"
fi

# Everything the site serves is staged here: the dmg, its notes, the appcast
# Sparkle reads and the small json the download page reads.
echo "==> stage release folder"
rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"
cp "$RELEASE_DMG" "$SITE_DIR/"
SITE_DMG="$SITE_DIR/$DMG_NAME"

DMG_SIZE=$(/usr/bin/stat -f%z "$SITE_DMG")
DMG_SHA=$(/usr/bin/shasum -a 256 "$SITE_DMG" | cut -d' ' -f1)
RELEASE_DATE=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

if [ -f "$PUBLISHED_APPCAST" ]; then
  cp "$PUBLISHED_APPCAST" "$SITE_DIR/appcast.xml"
fi

# Named after the dmg, which is how generate_appcast finds the notes for this
# item and embeds them in the feed. Write release-notes/<version>.md to say
# something better than the default.
NOTES="$SITE_DIR/${DMG_NAME%.dmg}.md"
if [ -f "release-notes/$VERSION.md" ]; then
  cp "release-notes/$VERSION.md" "$NOTES"
else
  cat > "$NOTES" <<NOTESFILE
Agent Caffeine $VERSION for Mac, build $BUILD.
NOTESFILE
fi

echo "==> sign dmg for sparkle"
ED_SIGNATURE=$(sparkle_tool sign_update -p "$SITE_DMG")

# --maximum-versions 0 keeps every older item instead of the newest three.
echo "==> generate appcast"
sparkle_tool generate_appcast \
  --download-url-prefix "$SITE_URL/" \
  --embed-release-notes \
  --maximum-versions 0 \
  "$SITE_DIR"

# generate_appcast only warns when the key does not match SUPublicEDKey, and
# then writes the item unsigned, which every shipped copy of the app refuses.
# The item for this dmg has to carry the signature of this dmg.
if ! grep -F "sparkle:edSignature=\"$ED_SIGNATURE\"" "$SITE_DIR/appcast.xml" | grep -qF "url=\"$DMG_URL\""; then
  echo "error: the appcast item for $DMG_URL does not carry this dmg's EdDSA" >&2
  echo "       signature." >&2
  exit 1
fi

echo "==> write latest.json"
cat > "$SITE_DIR/latest.json" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "url": "$DMG_URL",
  "filename": "$(download_name "$VERSION")",
  "size": $DMG_SIZE,
  "sha256": "$DMG_SHA",
  "date": "$RELEASE_DATE"
}
JSON

r2_put() {
  key="$1"
  file="$2"
  type="$3"
  if [ "$R2_TRANSPORT" = cf ]; then
    if [ "$DRY_RUN" = 1 ]; then
      echo "    would run: cf r2 objects put $key --bucket-name <R2_BUCKET> --file \"$file\" --content-type $type"
    else
      echo "    $key"
      cf r2 objects put "$key" --bucket-name "$R2_BUCKET" --file "$file" --content-type "$type"
    fi
    return
  fi
  url="$R2_S3_ENDPOINT/$R2_BUCKET/$key"
  if [ "$DRY_RUN" = 1 ]; then
    echo "    would run: curl --aws-sigv4 aws:amz:auto:s3 --upload-file \"$file\" -H \"Content-Type: $type\" <R2_S3_ENDPOINT>/<R2_BUCKET>/$key"
    return
  fi
  echo "    $key"
  # The Content-Type is all that is stored beside the object, as with cf. The
  # hash goes into the signature, so the bucket refuses any other bytes.
  sha=$(/usr/bin/shasum -a 256 "$file" | cut -d' ' -f1)
  : > "$S3_BODY"
  STATUS=$(s3_curl -o "$S3_BODY" --upload-file "$file" -H "Content-Type: $type" \
    -H "x-amz-content-sha256: $sha" "$url") || STATUS="no response"
  case "$STATUS" in
    2??) ;;
    *)
      echo "error: could not upload $key to the bucket over S3 ($STATUS)." >&2
      s3_reason "$S3_BODY"
      exit 1
      ;;
  esac
}

# The dmg goes up first and the feed last, so neither small file ever points at
# a download that is not there yet. Each upload is live at once.
if [ "$DRY_RUN" = 1 ]; then
  echo "==> skip upload to r2 (--dry-run)"
else
  echo "==> upload to r2"
fi
r2_put "mac/$DMG_NAME" "$SITE_DMG" "application/x-apple-diskimage"
r2_put "mac/latest.json" "$SITE_DIR/latest.json" "application/json"
r2_put "mac/appcast.xml" "$SITE_DIR/appcast.xml" "application/xml"

# The site serves what the bucket holds now. The query string keeps an older
# appcast that a cache may hold out of the check.
if [ "$DRY_RUN" = 0 ]; then
  echo "==> verify the upload on the site"
  UPLOADED_DMG="$BUILD_DIR/uploaded.dmg"
  curl -sSf -o "$UPLOADED_DMG" "$SITE_URL/$DMG_NAME"
  UPLOADED_SIZE=$(/usr/bin/stat -f%z "$UPLOADED_DMG")
  UPLOADED_SHA=$(/usr/bin/shasum -a 256 "$UPLOADED_DMG" | cut -d' ' -f1)
  rm -f "$UPLOADED_DMG"
  if [ "$UPLOADED_SIZE" != "$DMG_SIZE" ] || [ "$UPLOADED_SHA" != "$DMG_SHA" ]; then
    echo "error: $SITE_URL/$DMG_NAME is not this dmg:" >&2
    echo "       $UPLOADED_SIZE bytes, sha256 $UPLOADED_SHA" >&2
    echo "       expected $DMG_SIZE bytes, sha256 $DMG_SHA" >&2
    exit 1
  fi
  echo "    $SITE_URL/$DMG_NAME: $DMG_SIZE bytes, sha256 matches"
  UPLOADED_APPCAST=$(curl -sSf "$SITE_URL/appcast.xml?build=$BUILD-$(date +%s)")
  if ! grep -qF "<sparkle:version>$BUILD</sparkle:version>" <<< "$UPLOADED_APPCAST" \
    || ! grep -qF "url=\"$DMG_URL\"" <<< "$UPLOADED_APPCAST"; then
    echo "error: $SITE_URL/appcast.xml does not list build $BUILD at $DMG_URL." >&2
    exit 1
  fi
  echo "    $SITE_URL/appcast.xml: lists build $BUILD"
fi

echo ""
echo "✓ release artifacts:"
echo "  zip: $RELEASE_ZIP"
echo "  dmg: $SITE_DMG"
echo "  notes: $NOTES"
echo "  appcast: $SITE_DIR/appcast.xml"
echo "  latest: $SITE_DIR/latest.json"
echo ""
echo "  version: $VERSION (build $BUILD)"
echo "  dmg sha256: $DMG_SHA"
echo "  download url: $DMG_URL"
echo "  signed by: $(codesign -dvv "$APP" 2>&1 | grep 'Authority=' | head -1)"
if [ "$NOTARIZE" = 0 ]; then
  echo "  notarized: no (--dry-run)"
else
  echo "  notarized app: $(xcrun stapler validate "$APP" 2>&1 | tail -1)"
  echo "  notarized dmg: $(xcrun stapler validate "$SITE_DMG" 2>&1 | tail -1)"
fi
echo "  gatekeeper: $(spctl -a -t exec -vvv "$APP" 2>&1 | tail -1)"
if [ "$DRY_RUN" = 1 ]; then
  echo ""
  echo "  nothing was uploaded (--dry-run), so the site still serves the"
  echo "  release before this one."
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo ""
  echo "  next: the workflow writes the tag v$VERSION and the GitHub release."
else
  echo ""
  echo "  next: create the GitHub release v$VERSION from this commit, with"
  echo "  $SITE_DMG"
fi
