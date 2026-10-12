#!/usr/bin/env bash
# Fetches the licensed Suisse Intl woff2 files from a private Cloudflare R2
# bucket into app/fonts/, which git ignores. It never stops a build: without
# the three variables, or when a download fails, it warns and exits 0, and the
# site is built with its fallback face.
#   FONT_BUCKET            the name of the bucket that holds the two files at its root
#   CLOUDFLARE_ACCOUNT_ID  the account the bucket is in
#   CLOUDFLARE_API_TOKEN   a token that may read objects in that bucket

set -uo pipefail

cd "$(dirname "$0")/.."

DEST="app/fonts"
FILES=(SuisseIntl-Regular.woff2 SuisseIntl-Medium.woff2)

missing=()
for file in "${FILES[@]}"; do
  [[ -s "$DEST/$file" ]] || missing+=("$file")
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "fonts: Suisse Intl is in $DEST."
  exit 0
fi

if [[ -z "${FONT_BUCKET:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" || -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "fonts: FONT_BUCKET, CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are not all set. Suisse Intl is not fetched, and the fallback face is used."
  exit 0
fi

mkdir -p "$DEST"
for file in "${missing[@]}"; do
  url="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$FONT_BUCKET/objects/$file"
  # A woff2 file starts with the four letters wOF2. Anything else is an error page, and is not kept.
  if curl -fsS --retry 2 -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -o "$DEST/$file.part" "$url" \
    && [[ "$(head -c 4 "$DEST/$file.part")" == "wOF2" ]]; then
    mv "$DEST/$file.part" "$DEST/$file"
    echo "fonts: fetched $file."
  else
    rm -f "$DEST/$file.part"
    echo "fonts: could not fetch $file. The fallback face is used."
  fi
done
exit 0
