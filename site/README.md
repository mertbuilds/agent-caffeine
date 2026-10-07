# caffeinagent-site

The site for agent caffeine at caffeinagent.com. Next.js, run with `bun run dev`.

## Downloads

The app's release files (the dmg, `appcast.xml` and `latest.json`) are in the Cloudflare R2 bucket `agent-caffeine-mac` under `mac/`, public to read at `https://files.caffeinagent.com` (the value of `MAC_FILES_ORIGIN`), and the site serves them at `https://caffeinagent.com/mac/<file>`.

The site reads them over HTTPS with no credentials. Set `MAC_FILES_ORIGIN` to an origin that answers a GET for `/mac/<file>` without a login, written without a trailing slash (for example `https://<files-domain>`).

- Set it for the build. `next.config.js` reads it when the site is built and rewrites `/mac/*` to `${MAC_FILES_ORIGIN}/mac/*`. A build without it has no `/mac/` route.
- Set it for the running site too. The server reads `${MAC_FILES_ORIGIN}/mac/latest.json` (revalidated every hour) to decide whether the page shows the download button.

Without it the page shows only the buy button. The same happens while `latest.json` cannot be read, and the server log then says why.

To see the page with a download while none is published, put `NEXT_PUBLIC_FAKE_RELEASE=1` in `.env.development.local`. The dev server then shows a sample release whose link goes nowhere. A production build ignores it.

## Link preview picture

`public/og.png` (1200 by 630) is a picture of the page at `/og-image`, which only the dev server draws; a production build answers "not found" there. The page takes the price from `lib/pricing.ts`. After a change to the price, the headline or the icon, run `scripts/og-image.sh` with the dev server up and commit the new `public/og.png`. The script needs the `ego-browser` CLI.
