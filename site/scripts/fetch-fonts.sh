#!/usr/bin/env bash
# Fetches the licensed Suisse Intl woff2 files from a private Cloudflare R2
# bucket into app/fonts/, which git ignores, over the R2 S3 API. It never stops
# a build: without the four variables, or when a download fails, it warns and
# exits 0, and the site is built with its fallback face.
#   FONT_BUCKET            the name of the bucket that holds the two files at its root
#   CLOUDFLARE_ACCOUNT_ID  the account the bucket is in
#   R2_ACCESS_KEY_ID       an R2 S3 access key that may read objects in that bucket
#   R2_SECRET_ACCESS_KEY   the secret of that access key

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

if [[ -z "${FONT_BUCKET:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" || -z "${R2_ACCESS_KEY_ID:-}" || -z "${R2_SECRET_ACCESS_KEY:-}" ]]; then
  echo "fonts: FONT_BUCKET, CLOUDFLARE_ACCOUNT_ID, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY are not all set. Suisse Intl is not fetched, and the fallback face is used."
  exit 0
fi

mkdir -p "$DEST"
for file in "${missing[@]}"; do
  url="https://$CLOUDFLARE_ACCOUNT_ID.r2.cloudflarestorage.com/$FONT_BUCKET/$file"
  # A woff2 file starts with the four letters wOF2. Anything else is an error page, and is not kept.
  if curl -fsS --retry 2 --aws-sigv4 "aws:amz:auto:s3" --user "$R2_ACCESS_KEY_ID:$R2_SECRET_ACCESS_KEY" -o "$DEST/$file.part" "$url" \
    && [[ "$(head -c 4 "$DEST/$file.part")" == "wOF2" ]]; then
    mv "$DEST/$file.part" "$DEST/$file"
    echo "fonts: fetched $file."
  else
    rm -f "$DEST/$file.part"
    echo "fonts: could not fetch $file. The fallback face is used."
  fi
done
exit 0
