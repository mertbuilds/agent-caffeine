import localFont from "next/font/local";

/**
 * Suisse Intl, a licensed face. Its two files are not in the repository:
 * `scripts/fetch-fonts.sh` puts them in `app/fonts/`. Without them the build
 * takes `lib/fonts-fallback.ts` in place of this file (next.config.js).
 */
export const suisse = localFont({
  src: [
    { path: "../app/fonts/SuisseIntl-Regular.woff2", weight: "400", style: "normal" },
    { path: "../app/fonts/SuisseIntl-Medium.woff2", weight: "500", style: "normal" },
  ],
  variable: "--font-suisse",
  display: "swap",
  adjustFontFallback: false,
});
