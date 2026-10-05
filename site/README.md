# caffeinagent-site

The site for agent caffeine at caffeinagent.com. Next.js, run with `bun run dev`.

## Downloads

The app's release files (the dmg, `appcast.xml` and `latest.json`) live in a public Cloudflare R2 bucket under `mac/`, and the site serves them at `https://caffeinagent.com/mac/<file>`.

Set `MAC_FILES_ORIGIN` to the bucket's public origin, without a trailing slash (for example `https://<bucket-domain>`). With it set, `/mac/*` is rewritten to `${MAC_FILES_ORIGIN}/mac/*`, and the page reads `latest.json` (revalidated every hour) to show the download button, the version and the size. Without it, or while `latest.json` cannot be read, the page shows only the buy button.
