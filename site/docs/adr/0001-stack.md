# ADR-0001: Stack

Date: 2026-09-02. Status: accepted.

Full decision record from the founding grill session. One product = one copy of this repo (GitHub template, fork-and-diverge).

## Decisions

| Area        | Decision                                                                                                                                     | Why                                                                  |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Monorepo    | pnpm 11 workspaces + Turborepo, Node 24                                                                                                      | Task graph + remote cache; boring and stable                         |
| Web         | TanStack Start (React 19 + Compiler) on Cloudflare Workers                                                                                   | First-class Workers support; fetch-handler server entry              |
| API         | Fastify + oRPC + Better Auth + Prisma → Docker on Hetzner (Dokploy)                                                                          | Long-running Node runtime, prod = local container parity             |
| RPC         | oRPC                                                                                                                                         | OpenAPI-native → Scalar docs for free; typed client for web          |
| Auth        | Better Auth: email+password + Google. No orgs until needed                                                                                   | Minimal surface; cross-subdomain cookies                             |
| Billing     | `@better-auth/stripe` subscriptions                                                                                                          | Plans/trials integrated with auth                                    |
| DB          | Postgres 17, Prisma 7 (`@prisma/adapter-pg`, ESM client)                                                                                     | Committed migrations; `migrate deploy` on container start            |
| Lint/format | oxlint (+`@nkzw/oxlint-config`, type-aware + type-check via tsgolint) + oxfmt                                                                | Strict, error-only, fast; no ESLint/Prettier/Biome/Ultracite wrapper |
| Typecheck   | `tsc --noEmit` (TypeScript 7 native)                                                                                                         | Stable, debuggable, fast                                             |
| Tests       | Vitest; api = Testcontainers Postgres + truncate between tests; ui = Storybook stories as tests (`addon-vitest`); e2e = one Playwright smoke | Real DB, no mocks; components tested via stories                     |
| Styling     | StyleX tokens: black/white + 3 grays, 4px radius, 4px spacing, Suisse Intl by default (licensed, fetched), Inter fallback                    | One source of truth; grow on demand                                  |
| Components  | Base UI wrapped on demand (starter: Button, Input, Dialog)                                                                                   | Nothing unused                                                       |
| Analytics   | PostHog Cloud EU: replay + heatmaps, `/ingest/*` reverse proxy, `posthog-node` server events                                                 | Adblock-resistant, identified by auth userId                         |
| Errors      | Sentry (web + api), source maps in CI, uptime check on `/health`                                                                             | Stack traces, grouping, alerts                                       |
| Logging     | evlog wide events (fastify + tanstack-start), Axiom drain in staging/prod, `audit_log` table for mutations                                   | Searchable request logs + durable audit trail                        |
| i18n        | Paraglide v2, en-only structure; api returns error codes, web maps to messages                                                               | Compile-time typed messages; errors localizable                      |
| Local dev   | mprocs: postgres (compose) + emulate.dev (stripe/google/resend) + api + web + storybook. `stripe:listen` opt-in for subscription webhooks    | Fully offline local; agents break things freely                      |
| Envs        | local / staging / prod; zod-validated at boot                                                                                                | Fail fast on misconfig                                               |
| CI/CD       | GitHub Actions + turbo cache; push main → Dokploy webhook + cf deploy; Dokploy PR previews (schema-per-PR) + Workers preview URLs            | Proven path, previews for every PR                                   |
| Reviews     | cubic AI review + react-doctor in CI; branch protection                                                                                      | Quality gates that scale                                             |
| Skills/MCP  | skills-npm + skills CLI lock + pinned .mcp.json + Renovate + drift-check script                                                              | Agent knowledge tracks dependency versions                           |

## Known gaps

- emulate.dev Stripe has no subscription objects/events (only `checkout.session.completed|expired`); subscription webhook flow needs opt-in Stripe CLI or staging.
- TypeScript 7 has no programmatic API; tools importing `typescript` alias to `@typescript/typescript6`.
- oxfmt is 0.x (beta); Prettier-conformant for JS/TS.

## Drift during implementation (2026-09-02)

Deviations from the plan above, discovered while building. These are the current truth:

- **Prisma 7.10, not 8**: npm `latest` was 8.0.0-rc; RC skipped deliberately. Datasource URL lives in `prisma.config.ts` (Prisma 7 moved it out of the schema); runtime adapter (`@prisma/adapter-pg`) is constructed in `createDb`.
- **evlog on web uses `evlog/workers`**, not a `tanstack-start` adapter (doesn't exist in evlog 2.28); the custom `src/server.ts` Worker entry wraps the Start handler with paraglide + evlog. Axiom drain export is `createAxiomDrain`.
- **React Compiler via `@vitejs/plugin-react` v6 `compiler: true`** (oxc-transform-react): v6 removed the `babel` option, so no babel preset.
- **`/dashboard` is `ssr: false`**: the session cookie belongs to the api origin and isn't forwarded during SSR; an SSR auth check bounced logged-in users (found by e2e).
- **CORS is load-bearing**: web and api are always cross-origin (ports locally, subdomains in prod). `@fastify/cors` with `credentials: true`, origin from `WEB_URL`. Removing it hangs every browser auth call (found by e2e).
- **Pre-hydration guard**: root sets `data-hydrated` on `<html>`; e2e waits for it. Submitting a form before hydration triggers a native GET submit (credentials in URL).
- **Compose Postgres on host port 5433** (5432 commonly occupied); container-internal stays 5432.
- **skills-npm dropped**: no installed dep ships `skills/` in its npm tarball today; `skills` CLI lock + `skills.versions.json` drift check cover maintenance.
- **Better Auth CLI is stale** (1.4.x vs better-auth 1.7): auth schema was written against 1.7's canonical tables by hand; don't rerun `@better-auth/cli generate` blindly.
- **Stripe event idempotency guards only custom `onEvent` logic**: the plugin has no pre-hook; its built-in handlers are upsert-idempotent.
