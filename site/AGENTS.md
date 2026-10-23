# Agent Caffeine site

The caffeinagent.com website: a pnpm workspace in `site/` of the Agent Caffeine repo, started from mertbuilds/cleanstarter (renamed, backend trimmed), the same way as the SealClip site. The git root is one level up; run every command below from `site/` (or with `pnpm -C site`). The Mac app at the repo root does not depend on it. Product facts and applied blocks: `docs/product.md`. Keep it minimal: nothing gets added until the site needs it.

## Architecture

```
apps/
  web/    TanStack Start (React 19, React Compiler) → Cloudflare Workers.
          Thin: SSR, routes, Paraglide i18n, OpenPanel on the live host. No error tracker.
packages/
  ui/     StyleX tokens + Base UI wrappers + Storybook. Black and white, the app's blues, Suisse Intl.
  config/ Shared tsconfig base.
```

## Commands

| Command             | What                                                                       |
| ------------------- | -------------------------------------------------------------------------- |
| `pnpm dev`          | Full local stack via mprocs, one pane per service (`mprocs.yaml`)          |
| `pnpm lint`         | oxlint, type-aware + TS compiler errors (tsgolint)                         |
| `pnpm format`       | oxfmt (write mode); `pnpm format:check` in CI                              |
| `pnpm knip`         | Unused files, deps and exports (`knip.ts`); run after a build              |
| `pnpm typecheck`    | `tsc -p scripts` (repo scripts), then `tsc --noEmit` per package via turbo |
| `pnpm test`         | Vitest per package via turbo                                               |
| `pnpm build`        | turbo build                                                                |
| `pnpm bad-day`      | Nuke node_modules + all caches, reinstall (`DRY_RUN=1` to preview)         |
| `pnpm fonts`        | Fetch the licensed Suisse Intl files from R2 (README, Fonts)               |
| `pnpm skills:check` | Verify agent skills match dep majors and `skills-lock.json` hashes         |

Web app (`apps/web`): `pnpm --filter @caffeinagent/web dev` (:3000 standalone, or portless-assigned `PORT` under `pnpm dev`), `build` (Workers bundle; pins NODE_ENV=production because the root `.env` sets development, and `vite.config.ts` refuses a bare `vite build`), `cf:deploy` (`build` then `cf deploy --prebuilt`, same as CI; not `deploy`, which pnpm runs as its built-in `pnpm deploy`), `cf-typegen` (`cf workers types`, binding types).

## Blocks

- Blocks (reusable site pieces) and styles (skins over them) live in the `blocks/` and `styles/` folders of mertbuilds/cleanstarter. A site keeps no copy. Why: `docs/adr/0002-blocks.md`.
- Add one with the `add-block` skill (`/add-block <name>`, `--update` for a newer version). An app records its answers and applied `block@version` in `docs/product.md`.

## Local URLs (portless)

`pnpm dev` serves the HTTP apps behind [portless](https://portless.sh): stable named HTTPS URLs instead of ports:

| Service   | URL                                      | Without portless |
| --------- | ---------------------------------------- | ---------------- |
| web       | https://caffeinagent.localhost           | :3000            |
| storybook | https://storybook.caffeinagent.localhost | :6006            |

- First run needs one-time setup in a terminal: `sudo pnpm exec portless proxy start --https` (binds 443, generates + trusts a local CA). After that the proxy auto-starts. `pnpm exec portless service install` makes it start on boot.
- portless injects `PORT` (4000-4999 pool) into each app; vite reads it in `vite.config.ts`.

## UI (`packages/ui`)

- Components come from the [shadcn-cssinjs](https://www.shadcn-cssinjs.com) registry (StyleX on Base UI, copy-paste-own) into `src/ui/`, then adapted to this repo. The shadcn CLI currently fails on this registry's cross-registry deps; fetch item JSON from `https://www.shadcn-cssinjs.com/r/<name>.json` and write the files (adaptation checklist: relative imports, named stylex imports, `| undefined` on optional props for exactOptionalPropertyTypes). The `components.json` aliases (`#ui`, `#lib`) are package.json subpath imports (`"#*": "./src/*"` in `packages/ui/package.json`), so the CLI knows where files go, and TypeScript and Vite resolve them per package: they work from ui source in every consumer (web, Storybook) with no alias config. Never add a tsconfig `paths` alias instead: web typechecks ui source with its own compiler options, so it would pass in ui and fail in web. Source still uses relative imports.
- The palette is `src/tokens.css`: every colour once as `light-dark(light, dark)` under `color-scheme: light dark`, plus the motion and `--font-*` variables, as the Next site had them. `data-theme="light"|"dark"` on `<html>` (the footer's theme switch, `apps/web/src/lib/theme.ts`, set before the first paint by a head script) forces one side. Two token layers point at it: `src/tokens.stylex.ts` (app tokens: `colors` and `motion` as defineVars; `fontFamily`, `fontWeight`, `text`, `leading`, `spacing`, `radius`, `breakpoints` as defineConsts) and `src/lib/tokens.stylex.ts` (component tokens over the shadcn variables of `src/theme.css`, which point at the palette; `--border`, `--muted` and `--accent` are palette names, so the lib tokens read those directly). Components use the lib tokens; app layout uses the app tokens. Never raw color values.
- Global element styles (the web app's `src/styles/preflight.css`: Tailwind 3.4 preflight and the site's element rules) live in `@layer base`. StyleX emits into `@layer priorityN` and unlayered CSS beats every layer, so every StyleX plugin config (web vite + vitest, Storybook) passes `useCSSLayers: { before: ['base'] }`. A new consumer must do the same.
- `patches/@stylexjs__unplugin@<version>.patch` (`patchedDependencies` in `pnpm-workspace.yaml`) adds `sourceMaps: true` to the plugin's Babel call. Without it the plugin returns no source map, so served maps describe StyleX's output instead of the file and DevTools and devknobs grab show wrong lines. A StyleX bump needs the patch redone for the new version (`pnpm patch`, `pnpm patch-commit`); delete it once upstream `@stylexjs/unplugin` ships the fix.
- Radius: 8px surfaces (cards, dialogs, popovers; the lib radius scale is pinned to `--radius`), pill controls (`radius.full`). Font stack `'Suisse Intl', 'Inter Variable', 'Suisse Intl Fallback', system-ui`, as cleanstarter has it. Suisse woff2 files are licensed, gitignored (`packages/ui/fonts/`), fetched from a private R2 bucket with `pnpm fonts` (R2 S3 key pair that may only read it, README); without them the site builds and draws Inter (`@fontsource-variable/inter`), or "Suisse Intl Fallback" (`src/fonts-fallback.css`, Arial set to Suisse's measure) when Inter misses the first paint. `__root.tsx` preloads `fontUrls` from `@caffeinagent/ui/fonts` and links `@caffeinagent/ui/fonts-optional.css` (`font-display: optional`) rather than importing it; `cssInjectionTarget` in `vite.config.ts` keeps StyleX output out of it. Storybook imports `fonts.css` (`swap`). Only Regular (400) and Medium (500) are licensed, so no text goes above 500. Components inherit the font from the app body; they set none themselves.
- Control heights: every form control (Button, Input, Select trigger) takes its height from `controlHeight` in `src/lib/tokens.stylex.ts`, 36px `default` and 28px `sm`, so a field and its button line up. Never set a control height by hand.
- Current set: Button, Input, Field (label/error composition), Dialog, Select, Table, Label, Separator, Skeleton, Toaster (sonner, next-themes dropped), Tip (Base UI Popover with `openOnHover` where the primary input can hover, so click, Enter and screen readers reach it too; a Base UI Drawer bottom sheet where it cannot, `(hover: none)`), InfoTip (circled-i Tip trigger, `large`/`small`, 24px hit area). Grow on demand from the registry.
- A story is the test: every component has colocated `*.stories.tsx` with `play` interaction tests. `pnpm --filter @caffeinagent/ui test` runs them in real Chromium via the Storybook Vitest addon (Vitest browser mode). `pnpm storybook` serves them on :6006. In dev, StyleX CSS for a module exists only after Vite transforms it and otherwise reaches the page up to 150ms later over HMR, so `.storybook/preview.ts` fetches it in `beforeEach`; that is what lets `play` assert computed styles.

## Web (`apps/web`)

- TanStack Start on Cloudflare Workers, Worker `caffeinagent-web`. Custom entry `src/server.ts` (`worker.entrypoint` in `cloudflare.config.ts`) answers `www`/http with a 301 to the apex (`src/lib/canonical.ts`), moved addresses (`src/lib/redirects.ts`: `/support` 301 to `/#pricing`), `/mac/<file>` from the private R2 bucket `MAC_FILES` (`src/lib/mac-files.ts`) and `/download` (`src/lib/download.ts`) first (README, Mac files and the download), then wraps the Start handler with `paraglideMiddleware` and an evlog wide event per request (Axiom drain when `AXIOM_TOKEN`+`AXIOM_DATASET` set). Without that drain evlog writes to the console only, so Workers `observability` is on (logs, sampling 1); turn it off once the drain is bound, or logs are duplicated.
- Unknown paths render the root `notFoundComponent` (`src/components/not-found.tsx`): the sleeping robot, the way home and the footer. Only the root matches there, which is how the root `head()` gives it its own title.
- React Compiler is on (`react({ compiler: true })` via `oxc-transform-react`).
- devknobs loads in dev only (`__root.tsx`, dynamic import so production tree-shakes it). Keys: `⇧K` toggles the panel, `⇧G` grabs an element's context for a coding agent, `⇧C` inspects its styles.
- Favicon: `public/icon.png`, the app icon. `public/` also holds `og.png` (the share picture), `icon-1024.png` and `robot/` (the hero's layers), and `content/blog/*.md` the blog's articles, kept as the Next site had them (oxfmt skips `content/`).
- Layout: `src/routes/__root.tsx` (head and meta, theme script, skip link, `SiteHeader`, `HashScroll`, `Analytics`), `src/routes/index.tsx` (the home page: one component per section in `src/sections/`, in the Next site's order, then the `Footer`). The header (`src/components/site-header.tsx`) gathers into its pill and opens back out with `src/lib/morph.ts`; on a narrow window `src/components/site-menu.tsx` holds its links. Pills are `src/components/pill.ts`.
- Styles: `src/styles/preflight.css` (`@layer base`), `src/app.css` (StyleX injection target), `src/styles/scenes.css` (the Next site's keyframes and drawing classes, unlayered so they beat StyleX; elements take them as className strings beside StyleX props()), `src/styles/article.css` (the blog's Markdown body, `.article`).
- Prices: every price and the checkout and purchases links come from `src/lib/pricing.ts`. `LAUNCH_PRICE_ACTIVE` switches the launch price; the discount itself lives on the Polar checkout link, so end it in Polar at the same time.
- Analytics: OpenPanel, on `caffeinagent.com` and `www.caffeinagent.com` only (`src/lib/track.ts`); a local run or a preview loads and sends nothing. `src/components/analytics.tsx` keeps the visit's `utm_` tags and, with `VITE_OPENPANEL_CLIENT_ID` set at build time, starts OpenPanel (`src/lib/openpanel.ts`). The browser reaches OpenPanel through this site: `src/routes/api/op/$.ts` (`src/lib/openpanel-proxy.ts`) serves its scripts and passes events on to `analytics.vinena.studio`. Count an event with `track()`; `checkoutUrlWith()` (`src/lib/attribution.ts`) puts the visitor's tags on a Polar checkout link.
- i18n: Paraglide v2, `messages/en.json` only. Generated `src/paraglide/` and `src/routeTree.gen.ts` are gitignored build output: never edit them, they regenerate on `vite dev`/`build`. All user-facing strings go through `m.*()`.
- The build needs no network: `project.inlang/settings.json` loads the message-format plugin from `node_modules` (pinned devDependency), not a CDN. If it fails to load, paraglide compiles no messages and every page throws at render while the build exits 0, so `build.rolldownOptions.onLog` in `vite.config.ts` fails the build on an undefined import in our own code.
- StyleX in routes: import `../app.css` (build injection target); there is no importable `virtual:stylex.css` module; in dev the plugin middleware serves the CSS itself.
- StyleX does not order overlapping min-width media queries: a property with both an `sm` and an `md` value can take the `sm` one on a wide window. Bound the smaller one above (`src/components/footer.tsx`, `SM_ONLY`).

### i18n lint

- All user-facing strings go through Paraglide (`m.*()`). `react/jsx-no-literals` (oxlint, error) forbids hardcoded JSX text and text-bearing attributes (label/placeholder/title/alt/aria-\*); tests, stories, and scripts are exempt via overrides. `packages/ui` components take all text as props. Inline `oxlint-disable` only with a justification comment.

## Testing

Test pyramid, bottom-up, all run by `pnpm test` (turbo) unless noted:

- **Unit** (`*.test.ts` / `*.test.tsx`): web unit tests run in jsdom (Vitest + Testing Library); a test that needs a bare Node global scope says `// @vitest-environment node` (`src/lib/track.test.ts`).
- **Component** (`packages/ui`): stories are the tests, their `play` functions run in real Chromium via `@storybook/addon-vitest` (`pnpm --filter @caffeinagent/ui test`).

Conventions:

- New UI components get a story with a `play` test. Vite plugins for the story tests go in `.storybook/main.ts` only, because `storybookTest` applies the whole Storybook Vite config, so repeating a plugin in `packages/ui/vitest.config.ts` registers it twice and doubles transform work on a cold cache.

## Dev workflow

- `pnpm dev` runs mprocs with a pane per service in `mprocs.yaml`: web, storybook. Quit with `q`; panes restart individually with `r`.
- When everything is broken for no reason: `pnpm bad-day` (kills this checkout's dev processes, removes every node_modules/cache/generated dir, prunes the pnpm store, reinstalls). Preview with `DRY_RUN=1 pnpm bad-day`.
- Agent skills for the stack live in `.claude/skills/` (committed, pinned by `skills-lock.json`). Maintenance: `npx skills update` refreshes them; `pnpm skills:check` (strict, fails CI) flags a dep whose installed major drifts from what its skill was last verified against (`skills.versions.json`) and a vendored skill whose files no longer match its `skills-lock.json` `computedHash`. After a major dep bump, update the skill, re-verify, bump `checkedMajor`.

## CI/CD

- **CI** (`.github/workflows/site-ci.yml` at the repo root, PRs and main, on changes under `site/`; every step runs in `site/`). Turbo remote cache activates when `TURBO_TOKEN`/`TURBO_TEAM` are configured.
  - `checks` job: turbo typecheck/build, then root `pnpm lint` (type-aware, so it runs after the build generates `routeTree.gen.ts`) + `format:check` + `skills:check` + `knip` + react-doctor (warnings shown, errors fail; `doctor.config.json` lets `src/lib/morph.ts` animate the pill ground's edges, since a scale would stretch its corners) + `scripts/smoke-web.sh`.
  - `test` job: `turbo run test` minus `@caffeinagent/ui` (web jsdom).
  - `test-ui` job: the Chromium story tests alone.
- **Deploy and previews**: not set up yet. `scripts/smoke-web.sh` serves the build with `vite preview` and requires each page in its `PAGES` to answer 200 with the app title.
- Required repo config lives in README's "Going to production" checklist. CI must be green before merge.

## Rules

- Never edit generated directories:
  - `apps/web/src/paraglide/`
- No new dependencies, components, or abstractions without a concrete current need.
- Secrets never enter git. Local uses `.env` (from `.env.example`); prod uses Workers secrets (`cf workers secrets`).
- PRs only against `main`; CI must be green.
- Stack decisions are recorded in `docs/adr/`. Change of direction = new ADR.
