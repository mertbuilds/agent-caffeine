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

OpenPanel counts page views on `caffeinagent.com` and `www.caffeinagent.com` only. A local run or a preview loads no script and sends nothing. The OpenPanel project is `VITE_OPENPANEL_CLIENT_ID`, read at build time; without it nothing loads. The browser reaches OpenPanel through `/api/op` on the site itself, so a content blocker does not drop it.

## Fonts

The site is set in Suisse Intl, a licensed typeface. Its files are not in this repository, and git ignores `packages/ui/fonts/*.woff2`.

- Without the files the site builds and runs, set in Inter, or in Arial with the measures of Suisse Intl.
- `pnpm fonts` (`scripts/fetch-fonts.sh`) fetches `SuisseIntl-Regular.woff2` and `SuisseIntl-Medium.woff2` from a private Cloudflare R2 bucket into `packages/ui/fonts/`, over the R2 S3 API. It needs `FONT_BUCKET`, `CLOUDFLARE_ACCOUNT_ID`, and an R2 S3 access key that may only read that bucket in `R2_ACCESS_KEY_ID` and `R2_SECRET_ACCESS_KEY` (one key per job, `../docs/adr/0002-release-keys-scoped-per-job.md`). It never stops a build.
- If you have your own license for Suisse Intl, put the two files in `packages/ui/fonts/` yourself.

## Going to production

Not set up yet. Local dev needs none of these. Production needs:

- [ ] **Cloudflare**: the Worker `caffeinagent-web`; secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` in GitHub, and for the fonts `FONT_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (a read-only key for the fonts bucket); deploys ship only after `scripts/smoke-web.sh` sees the built site render
- [ ] **OpenPanel**: the variable `OPENPANEL_CLIENT_ID`, passed to the build as `VITE_OPENPANEL_CLIENT_ID`
- [ ] **Axiom** (optional): dataset + token for evlog drain, then turn Workers `observability` off in `apps/web/cloudflare.config.ts`
- [ ] **Turbo remote cache** (optional): `TURBO_TOKEN` secret + `TURBO_TEAM` var

## License

Copyright (C) 2026 Mert Duzgun. All rights reserved.

See [TRADEMARKS.md](TRADEMARKS.md). The licenses of other people's work in this repository are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
