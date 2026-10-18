# caffeinagent-site

The website of Agent Caffeine at [caffeinagent.com](https://caffeinagent.com). Agent Caffeine is a free and open source macOS menu bar app that keeps a Mac awake while AI coding agents work. The app's own code is at [github.com/mertbuilds/agent-caffeine](https://github.com/mertbuilds/agent-caffeine).

The site is a Next.js app with Tailwind CSS.

## Run it

You need [Bun](https://bun.sh).

```sh
bun install
bun run dev
```

- `bunx tsc --noEmit` checks the types.
- `bun test` runs the tests.
- `bun run build` builds the site. It needs no variable and no font file.

## Variables

All of them are optional. None has a value in this repository.

| Variable | What it does |
| --- | --- |
| `MAC_FILES_ORIGIN` | The origin that serves the app's release files under `/mac/` (see Downloads). |
| `NEXT_PUBLIC_FAKE_RELEASE` | `1` makes the dev server show a sample release. A production build ignores it. |
| `NEXT_PUBLIC_SUPPORT_URL` | The GitHub Sponsors page that the button on `/support` opens. Without it the page says that support is not set up yet. |
| `NEXT_PUBLIC_OPENPANEL_CLIENT_ID` | The OpenPanel project that counts page views and downloads. |
| `OPENPANEL_CLIENT_SECRET` | Lets the server count a download. Server only: never give it a `NEXT_PUBLIC_` name. |
| `FONT_BUCKET`, `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` | Where `scripts/fetch-fonts.sh` gets the licensed fonts from (see Fonts). |

## Downloads

The app's release files (the dmg, `appcast.xml` and `latest.json`) are in a storage bucket that is public to read, and the site serves them at `https://caffeinagent.com/mac/<file>`.

The site reads them over HTTPS with no credentials. Set `MAC_FILES_ORIGIN` to an origin that answers a GET for `/mac/<file>` without a login, written without a trailing slash (for example `https://<files-domain>`).

- Set it for the build. `next.config.js` reads it when the site is built and rewrites `/mac/*` to `${MAC_FILES_ORIGIN}/mac/*`. A build without it has no `/mac/` route.
- Set it for the running site too. The server reads `${MAC_FILES_ORIGIN}/mac/latest.json` (revalidated every hour) to decide whether the page shows the download button.

Without it the page says that the download is not ready yet, and the header links to the source code. The same happens while `latest.json` cannot be read, and the server log then says why. The page never shows a price.

To see the page with a download while none is published, put `NEXT_PUBLIC_FAKE_RELEASE=1` in `.env.development.local`. The dev server then shows a sample release whose link goes nowhere.

## Download count

Every download button links to `/download?from=<placement>`. The route (`app/download/route.ts`) counts the download on the server and answers with a redirect to the dmg under `/mac/`. It needs no script in the browser, so a content blocker does not hide it.

- What is counted: one event named `download`, with the version, the build, the placement (`header`, `menu`, `hero`, `pricing`, `blog`, `footer`, else `other`) and `utm_source`, `utm_medium` and `utm_campaign` when the link carries them. OpenPanel takes the country and the device from the visitor's IP address and user agent, which the route sends on. The site stores nothing and sets no cookie.
- What is not counted: requests off `caffeinagent.com` and `www.caffeinagent.com`, bots, prefetches and `HEAD` requests. They still get the redirect. `robots.txt` keeps crawlers away from `/download`.
- Off a Mac (a phone, a tablet, Windows, Linux), a click on a download button starts no download. The browser opens a popup that gives the site's link to copy or share on to a Mac, and counts the event `download_blocked_not_mac` with the placement. The link itself is the same for everyone, and `/download` still answers every request.
- Without `OPENPANEL_CLIENT_SECRET` and `NEXT_PUBLIC_OPENPANEL_CLIENT_ID` the route only redirects.

## Fonts

The site is set in Suisse Intl, a licensed typeface. Its files are not in this repository, and git ignores `app/fonts/`.

- Without the files the site builds and runs. The text is then set in Arial with the measures of Suisse Intl, or in the system's face.
- `bun run fonts` (`scripts/fetch-fonts.sh`) fetches `SuisseIntl-Regular.woff2` and `SuisseIntl-Medium.woff2` from a private Cloudflare R2 bucket into `app/fonts/`. It needs `FONT_BUCKET`, `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. `bun run build` runs it first. It never stops a build.
- If you have your own license for Suisse Intl, put the two files in `app/fonts/` yourself.

## Link preview picture

`public/og.png` (1200 by 630) is a picture of the page at `/og-image`, which only the dev server draws; a production build answers "not found" there. After a change to the headline or the icon, run `scripts/og-image.sh` with the dev server up and commit the new `public/og.png`. The script needs the `ego-browser` CLI. `OG_URL` names another address for the page.

## License

Copyright (C) 2026 Mert Duzgun.

The code of this site is under the GNU Affero General Public License, version 3 (`AGPL-3.0-only`). See [LICENSE](LICENSE).

Three things are not under that license:

- The name Agent Caffeine.
- The app icon and the robot art (`app/icon.png`, `public/icon-1024.png`, `public/robot/`, `public/og.png`, and the robot drawn in `components/robot.tsx`).
- The Suisse Intl fonts, which are not in this repository.

See [TRADEMARKS.md](TRADEMARKS.md). The licenses of other people's work in this repository are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
