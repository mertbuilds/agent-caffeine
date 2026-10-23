# Agent Caffeine website

The website of Agent Caffeine at [caffeinagent.com](https://caffeinagent.com). Agent Caffeine is a macOS menu bar app that keeps a Mac awake while AI coding agents work. It has a 7-day free trial, and a license key is paid once.

A pnpm workspace in `site/`, started from mertbuilds/cleanstarter (renamed to caffeinagent, backend trimmed), on Cloudflare Workers. The Mac app lives at the repository root and does not depend on it. Agent rules and workflow live in [AGENTS.md](AGENTS.md); founding decisions of the starter in [docs/adr/](docs/adr/); product facts in [docs/product.md](docs/product.md).

## Stack

| Layer       | Choice                                                                 |
| ----------- | ---------------------------------------------------------------------- |
| Monorepo    | pnpm workspaces + Turborepo, Node 24, TypeScript 7                     |
| Web         | TanStack Start (React 19 + Compiler) on Cloudflare Workers             |
| Styling     | StyleX tokens + Base UI components + Storybook                         |
| i18n        | Paraglide v2 (en only)                                                 |
| Analytics   | OpenPanel, on the live host only, through the site's `/api/op` proxy   |
| Logging     | evlog wide events, Axiom drain when bound                              |
| Lint/format | oxlint (`@nkzw/oxlint-config`, type-aware) + oxfmt, no ESLint/Prettier |
| Tests       | Vitest (jsdom units, Storybook stories as tests)                       |
| Dev tools   | devknobs preference panel (`⇧K`) and element grab (`⇧G`), dev only     |

## Quickstart

Prereqs: Node 24 (`nvm use`), pnpm 11 (corepack). Run from `site/`, or add `-C site` from the repository root.

```sh
pnpm install
sudo pnpm exec portless proxy start --https   # one-time: local HTTPS proxy on 443 + trusted CA
pnpm dev        # mprocs: one pane per service
```

Open https://caffeinagent.localhost. Storybook is at https://storybook.caffeinagent.localhost.

## Commands

| Command                                        | What it does                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------ |
| `pnpm dev`                                     | Everything, in mprocs panes                                        |
| `pnpm test`                                    | Every Vitest suite (turbo)                                         |
| `pnpm lint` / `pnpm format` / `pnpm typecheck` | Quality gates (same as CI)                                         |
| `pnpm storybook`                               | Component workshop (standalone, :6006)                             |
| `pnpm fonts`                                   | Fetch the licensed Suisse Intl files (see Fonts)                   |
| `pnpm bad-day`                                 | Nuke node_modules + all caches, reinstall (`DRY_RUN=1` to preview) |
| `pnpm skills:check`                            | Fail on skill drift: dep majors or `skills-lock.json` hashes       |
| `pnpm knip`                                    | Fail on unused files, deps and exports (after a build)             |
| `bash scripts/smoke-web.sh`                    | Serve the build and check each page renders (after a build)        |

## Price

Every price on the site comes from `apps/web/src/lib/pricing.ts`: the full price, the launch price, the number of Macs, the Polar checkout link and the link to a buyer's purchases. `LAUNCH_PRICE_ACTIVE` switches the launch price. The discount itself lives on the Polar checkout link, so end it in Polar at the same time. `/support`, where older versions of the app link, redirects to the price on the home page.

## Analytics

OpenPanel counts page views on `caffeinagent.com` and `www.caffeinagent.com` only. A local run or a preview loads no script and sends nothing. The OpenPanel project is `VITE_OPENPANEL_CLIENT_ID`, read at build time; without it nothing loads. The browser reaches OpenPanel through `/api/op` on the site itself, so a content blocker does not drop it. Downloads are counted on the server: `/download` sends a person's download on a Mac to OpenPanel when the Worker secret `OPENPANEL_CLIENT_SECRET` is set, and always answers with the redirect.

## Fonts

The site is set in Suisse Intl, a licensed typeface. Its files are not in this repository, and git ignores `packages/ui/fonts/*.woff2`.

- Without the files the site builds and runs, set in Inter, or in Arial with the measures of Suisse Intl.
- `pnpm fonts` (`scripts/fetch-fonts.sh`) fetches `SuisseIntl-Regular.woff2` and `SuisseIntl-Medium.woff2` from a private Cloudflare R2 bucket into `packages/ui/fonts/`, over the R2 S3 API. It needs `FONT_BUCKET`, `CLOUDFLARE_ACCOUNT_ID`, and an R2 S3 access key that may only read that bucket in `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (one key per job, `../docs/adr/0002-release-keys-scoped-per-job.md`). It never stops a build.
- If you have your own license for Suisse Intl, put the two files in `packages/ui/fonts/` yourself.

## Mac files and the download

The Worker answers `/mac/<file>` from a private R2 bucket (binding `MAC_FILES` in `apps/web/cloudflare.config.ts`, bucket `caffeinagent-mac`, key = the path without its leading slash) through `apps/web/src/lib/mac-files.ts`, and `/download` with a 302 to the dmg that `mac/latest.json` names, or to `/` while there is none (`apps/web/src/lib/download.ts`). Pages read the newest release with `getLatestRelease` (`apps/web/src/lib/latest-release.functions.ts`). `scripts/release.sh` at the repository root uploads the files. Why: `../docs/adr/0003-site-on-workers-from-cleanstarter.md`.

`vite dev` reads a simulated bucket under `apps/web/.cloudflare/state`, empty at first, so `/download` goes home. To try a release locally, seed it from `apps/web`:

```sh
pnpm exec cf r2 objects put mac/agent-caffeine-0.3.0-20.dmg --bucket-name caffeinagent-mac --file <any file> --content-type application/x-apple-diskimage --local --persist-to .cloudflare/state
pnpm exec cf r2 objects put mac/latest.json --bucket-name caffeinagent-mac --file latest.json --content-type application/json --local --persist-to .cloudflare/state
```

`latest.json` as `release.sh` writes it: `{"version": "0.3.0", "build": "20", "url": "https://caffeinagent.com/mac/agent-caffeine-0.3.0-20.dmg", "filename": "agent-caffeine-0.3.0.dmg", "size": 4096}`. Without `--persist-to`, cf writes to `~/.config/cloudflare/state`, which `vite dev` never reads. `rm -rf apps/web/.cloudflare/state` empties it again.

## Blog

The articles are `apps/web/content/blog/*.md`, with frontmatter (`title`, `description`, `date`, `updated`, `faq`). `apps/web/vite-plugin-blog.ts` reads and renders them at build time (gray-matter and marked) into two virtual modules: `virtual:blog/index` for lists and `virtual:blog/posts` for the bodies, which load only on a post. A post names the price as `{{price}}`, so it follows `lib/pricing.ts`. `/compare`, `/llms.txt`, `/sitemap.xml` and `/robots.txt` are routes in `apps/web/src/routes/`.

## Share picture

`apps/web/public/og.png` is a picture of the dev-only page `/og-image`. With the dev server up, `bash scripts/og-image.sh` takes it again (ego-browser, devknobs hidden, converted to sRGB). `OG_URL` names another address for the page. After a change to the price, the headline or the icon, take it again and commit the new `og.png`.

## Going to production

Not set up yet. Local dev needs none of these. Production needs:

- [ ] **Cloudflare**: the Worker `caffeinagent-web`; the private R2 bucket `caffeinagent-mac` (binding `MAC_FILES`) with the release files copied over from the public one, then `files.caffeinagent.com` removed; secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` in GitHub, and for the fonts `FONT_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (a read-only key for the fonts bucket); deploys ship only after `scripts/smoke-web.sh` sees the built site render
- [ ] **OpenPanel**: the variable `OPENPANEL_CLIENT_ID`, passed to the build as `VITE_OPENPANEL_CLIENT_ID`, and the Worker secret `OPENPANEL_CLIENT_SECRET` for the download count
- [ ] **Axiom** (optional): dataset + token for evlog drain, then turn Workers `observability` off in `apps/web/cloudflare.config.ts`
- [ ] **Turbo remote cache** (optional): `TURBO_TOKEN` secret + `TURBO_TEAM` var

## License

Copyright (C) 2026 Mert Duzgun. All rights reserved.

See [TRADEMARKS.md](TRADEMARKS.md). The licenses of other people's work in this repository are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
