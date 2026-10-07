#!/usr/bin/env bash
# Saves the picture for link previews as public/og.png, from the dev-only page
# /og-image. Run it with the dev server up:
#   scripts/og-image.sh
# OG_URL names another address for that page.

set -euo pipefail

cd "$(dirname "$0")/.."

# The browser script runs inside ego-browser, which knows neither this folder
# nor this shell's variables, so both values are written into it.
sed -e "s|__OUT__|$PWD/public/og.png|" -e "s|__URL__|${OG_URL:-https://caffeinagent.local/og-image}|" <<'JS' | ego-browser nodejs
const task = await taskSpace("og image");
const page = task.page("p1");
try {
  await page.cdp("Emulation.setDeviceMetricsOverride", { width: 1200, height: 630, deviceScaleFactor: 1, mobile: false });
  await page.goto("__URL__");
  await page.waitForFunction(() => document.fonts.status === "loaded" && [...document.images].every((image) => image.complete));
  // The dev tools draw over the page, and they are not part of the picture.
  await page.evaluate(() => {
    for (const element of document.querySelectorAll("nextjs-portal, body > :not(main, script, style)")) element.remove();
  });
  await page.screenshot({ path: "__OUT__" });
  console.log("__OUT__");
} finally {
  await task.finish({ keep: [] });
}
JS
