# caffeinagent-site

The site for Agent Caffeine at caffeinagent.com. Next.js, run with `bun run dev`.

## Downloads

The app's release files (the dmg, `appcast.xml` and `latest.json`) are in the Cloudflare R2 bucket `agent-caffeine-mac` under `mac/`, public to read at `https://files.caffeinagent.com` (the value of `MAC_FILES_ORIGIN`), and the site serves them at `https://caffeinagent.com/mac/<file>`.

The site reads them over HTTPS with no credentials. Set `MAC_FILES_ORIGIN` to an origin that answers a GET for `/mac/<file>` without a login, written without a trailing slash (for example `https://<files-domain>`).

- Set it for the build. `next.config.js` reads it when the site is built and rewrites `/mac/*` to `${MAC_FILES_ORIGIN}/mac/*`. A build without it has no `/mac/` route.
- Set it for the running site too. The server reads `${MAC_FILES_ORIGIN}/mac/latest.json` (revalidated every hour) to decide whether the page shows the download button.

Without it the page shows only the buy button. The same happens while `latest.json` cannot be read, and the server log then says why.

To see the page with a download while none is published, put `NEXT_PUBLIC_FAKE_RELEASE=1` in `.env.development.local`. The dev server then shows a sample release whose link goes nowhere. A production build ignores it.

## Download count

Every download button links to `/download?from=<placement>`. The route (`app/download/route.ts`) counts the download on the server and answers with a redirect to the dmg under `/mac/`. It needs no script in the browser, so a content blocker does not hide it.

- What is counted: one event named `download`, with the version, the build, the placement (`header`, `menu`, `hero`, `pricing`, `blog`, `footer`, else `other`) and `utm_source`, `utm_medium` and `utm_campaign` when the link carries them. OpenPanel takes the country and the device from the visitor's IP address and user agent, which the route sends on. The site stores nothing and sets no cookie.
- What is not counted: requests off `caffeinagent.com` and `www.caffeinagent.com`, bots, prefetches and `HEAD` requests. They still get the redirect. `robots.txt` keeps crawlers away from `/download`.
- Where to see it: the OpenPanel project `caffeinagent`, event `download`.
- Off a Mac (a phone, a tablet, Windows, Linux), a click on a download button starts no download. The browser opens a popup that gives the site's link to copy or share on to a Mac, and counts the event `download_blocked_not_mac` with the placement. The link itself is the same for everyone, and `/download` still answers every request.
- `OPENPANEL_CLIENT_SECRET` must be set on Vercel, for production only, next to `NEXT_PUBLIC_OPENPANEL_CLIENT_ID`. Without it the route only redirects.

## Link preview picture

`public/og.png` (1200 by 630) is a picture of the page at `/og-image`, which only the dev server draws; a production build answers "not found" there. The page takes the price from `lib/pricing.ts`. After a change to the price, the headline or the icon, run `scripts/og-image.sh` with the dev server up and commit the new `public/og.png`. The script needs the `ego-browser` CLI.
