const { existsSync } = require("node:fs");
const { join } = require("node:path");

const macFilesOrigin = process.env.MAC_FILES_ORIGIN;

// Suisse Intl is licensed and not in the repository (scripts/fetch-fonts.sh). Without its files the build takes the fallback.
const hasFonts = ["SuisseIntl-Regular.woff2", "SuisseIntl-Medium.woff2"].every((file) =>
  existsSync(join(__dirname, "app/fonts", file)),
);

/** @type {import('next').NextConfig} */
module.exports = {
  reactStrictMode: true,
  // The portless dev URLs; without them Next refuses the dev client and the page never hydrates.
  allowedDevOrigins: ["caffeinagent.local", "caffeinagent.localhost"],
  turbopack: hasFonts ? {} : { resolveAlias: { "@/lib/fonts": "./lib/fonts-fallback.ts" } },
  // The app, the README and old links open `/support`, which is now a section of the home page.
  async redirects() {
    return [{ source: "/support", destination: "/#support", permanent: true }];
  },
  async rewrites() {
    if (!macFilesOrigin) return [];
    return [{ source: "/mac/:path*", destination: `${macFilesOrigin}/mac/:path*` }];
  },
};
