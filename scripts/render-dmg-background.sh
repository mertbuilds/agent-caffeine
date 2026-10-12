#!/usr/bin/env bash
# Render scripts/dmg-background.html to the two pictures dmgbuild reads:
# dmg-background.png (680x540) and dmg-background@2x.png (1360x1080).
#
#   bash scripts/render-dmg-background.sh
#
# Both pictures are tracked, so a release does not run this. Run it after a
# change to the html and commit the result.
#
# It needs Google Chrome (or CHROME pointed at any Chromium) and, for the real
# typeface, the two Suisse Intl files in scripts/fonts. Suisse Intl is a
# commercial typeface, so the files are not in this repo and scripts/fonts is
# gitignored. Copy your licensed files there, or point FONT_SOURCE at a folder
# that holds them.

set -euo pipefail

cd "$(dirname "$0")"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
  echo "error: no browser at $CHROME. point CHROME at a Chromium binary." >&2
  exit 1
fi

FONT_SOURCE="${FONT_SOURCE:-}"
FACES="SuisseIntl-Regular.woff2 SuisseIntl-Medium.woff2"
for face in $FACES; do
  if [ ! -f "fonts/$face" ] && [ -n "$FONT_SOURCE" ] && [ -f "$FONT_SOURCE/$face" ]; then
    mkdir -p fonts
    cp "$FONT_SOURCE/$face" "fonts/$face"
  fi
  if [ ! -f "fonts/$face" ]; then
    echo "error: fonts/$face is missing, so the picture would be set in the" >&2
    echo "       system font. copy the file into scripts/fonts, or set" >&2
    echo "       FONT_SOURCE to the folder that holds it." >&2
    exit 1
  fi
done

# The page loads the app icon from ../assets, so the server serves the repo
# root and the page is read from scripts/.
PORT="${PORT:-8765}"
PROFILE=$(mktemp -d)
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory .. >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; rm -rf "$PROFILE"' EXIT
sleep 1

# Chrome writes the picture and then does not always quit, so it runs beside
# the script and is stopped once the file is there. Its page is shorter than
# the window it is asked for and it fills the rest with a repeat of the top, so
# the window is taller than the art and the picture is cut back to the art.
# sips reads a crop offset of 0 as "center", so the picture gets a 1px frame
# first and the cut starts at 1.
WIDTH=680
HEIGHT=540
SPARE=200

render() {
  local scale=$1 out=$2 browser waited=0
  local w=$((WIDTH * scale)) h=$((HEIGHT * scale)) tall=$(((HEIGHT + SPARE) * scale))
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --user-data-dir="$PROFILE" --window-size="$WIDTH,$((HEIGHT + SPARE))" \
    --force-device-scale-factor="$scale" --virtual-time-budget=5000 \
    --screenshot="$(pwd)/$out" "http://127.0.0.1:$PORT/scripts/dmg-background.html" >/dev/null 2>&1 &
  browser=$!
  until [ -s "$out" ] || [ "$waited" -ge 60 ]; do
    sleep 1
    waited=$((waited + 1))
  done
  sleep 1
  kill "$browser" 2>/dev/null || true
  wait "$browser" 2>/dev/null || true
  if [ ! -s "$out" ]; then
    echo "error: the browser did not write $out" >&2
    exit 1
  fi
  sips -p $((tall + 2)) $((w + 2)) "$out" >/dev/null
  sips --cropOffset 1 1 -c "$h" "$w" "$out" >/dev/null
  echo "  $out: $(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixel/ {print $2}' | paste -sd x -)"
}

echo "==> render dmg background"
render 1 dmg-background.png
render 2 dmg-background@2x.png
