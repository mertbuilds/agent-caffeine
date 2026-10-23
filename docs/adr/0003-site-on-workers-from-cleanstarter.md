# 3. The site on Cloudflare Workers, from cleanstarter

Date: 2026-10-23. Status: accepted. Amends the last point of `docs/adr/0002-release-keys-scoped-per-job.md` (checks go to the bucket URL). The same setup as SealClip and Attention Awareness.

## Context

The site was a Next.js app on Vercel, and the release files were in an R2 bucket that was public at `files.caffeinagent.com`, with a Vercel rewrite of `/mac/*` to it (`MAC_FILES_ORIGIN`). The owner's other sites start from mertbuilds/cleanstarter and run on Cloudflare Workers, and the zone `caffeinagent.com` is on Cloudflare already. A public bucket host is a second address for every release file, and Cloudflare cached its 404s for hours, so the release checks had to avoid the site.

## Decision

- `site/` is a cleanstarter workspace (TanStack Start on Workers), deployed as the Worker `caffeinagent-web`. The Worker sends `www` and plain http to `https://caffeinagent.com` with a 301 (`site/apps/web/src/lib/canonical.ts`).
- The dmg, `appcast.xml` and `latest.json` live in a private R2 bucket (suggested name `caffeinagent-mac`) under `mac/`, bound to the Worker as `MAC_FILES`. It has no custom domain and no r2.dev URL. The Worker serves `/mac/<file>` from it (`site/apps/web/src/lib/mac-files.ts`): GET and HEAD, one byte range, conditional requests, a 404 for any other shape. `/mac/*` runs the Worker first, so no static asset can shadow a release file.
- `/download` is answered by the Worker too: it reads `mac/latest.json` from the bucket and redirects (302, no-store) to the newest dmg under `/mac/`, or to `/` while there is none. Pages read the same file through `getLatestRelease` (`site/apps/web/src/lib/latest-release.functions.ts`).
- `scripts/release.sh` uploads with a bucket-scoped key pair, the dmg first. Its checks before the upload ask the bucket, and its checks after the upload read `caffeinagent.com/mac/`. `scripts/release-request.sh` reads the appcast from `caffeinagent.com/mac/appcast.xml`.
- The blog's Markdown is read and rendered at build time (`site/apps/web/vite-plugin-blog.ts`), so the Worker reads no files at runtime.

## Consequences

- `SUFeedURL` stays `https://caffeinagent.com/mac/appcast.xml` for every shipped copy. `files.caffeinagent.com` goes away once the files are in the private bucket.
- A release is live the moment its upload ends; no site deploy is needed.
- A dmg is saved as `agent-caffeine-<version>.dmg`: the Worker sets the Content-Disposition, which `cf r2 objects put` cannot store.
- A Worker answer is not kept in Cloudflare's cache, so a 404 asked for before the upload is not served after it.
- Local dev reads a simulated bucket under `site/apps/web/.cloudflare/state`, seeded by hand (`site/README.md`).
