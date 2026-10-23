# ADR-0002: Blocks

Date: 2026-10-15. Status: accepted.

Goal: a new site (landing page, optional app) in about an hour. An agent asks the owner a few questions and assembles the site from reusable pieces. Patterns the owner asked for again and again (morph pill header, no macOS elastic scroll, hero background pattern, in-focus motion scenes, a download button that sends the link to a Mac) become those pieces.

## Decisions

| Area       | Decision                                                                                                                                                                                                                                | Why                                                                    |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Base       | Clean base (web + api + ui tokens) plus additive blocks that an agent adds                                                                                                                                                              | Adding what a site needs beats deleting what it does not               |
| Home       | Canonical block code lives in `blocks/<name>/`: generalized, StyleX, with tests. Product repos only consume blocks                                                                                                                      | One place to fix a pattern; products do not fork it                    |
| Style      | A style (`styles/lander-001/`) is a skin over style-agnostic blocks: tokens, header shape, hero pattern, motion language, default block list. Blocks style only via tokens and slots                                                    | lander-002 reuses the same blocks                                      |
| Facts      | One shared fact list (`blocks/facts.md`) with router questions. A block declares `needs-when` and the facts it asks. Answers and `block@version` persist in the app's `docs/product.md`                                                 | A later block reuses earlier answers and asks only for new facts       |
| Harvest    | A pattern asked for twice becomes a block. Sites record block versions. `/add-block <name> --update` re-applies a newer version on request. No auto-sync                                                                                | Blocks grow from real sites; updates stay the owner's call             |
| Sites      | A generated site keeps no `blocks/` or `styles/`; `add-block` reads them from the cleanstarter source. `product.kind` defaults to what the owner described, else `waitlist`. `download.url` keeps its default, since it is always asked | The site holds only what it applied; one source of truth for blocks    |
| Engine     | The `add-block` skill (`.claude/skills/add-block/`) asks, applies, verifies and records. Apply steps are prose for an agent, not a codemod                                                                                              | Each app differs a little; an agent adapts where a codemod would break |
| Tests      | `blocks/` is a workspace package; each block's tests run in CI against `packages/ui`, and again in the app after apply                                                                                                                  | A block is proven before any site takes it                             |
| lander-001 | v1 scope, in later PRs: shell (header, overscroll, fonts, favicons, analytics gating, UTM), hero and motion, Mac app (download CTA, send-to-Mac, update feed), conversion (FAQ, waitlist, OG rules). Reference look: the Angaria site   | The patterns asked for most, in the order a site needs them            |

## Known gaps

- Only `send-to-mac` and `waitlist` exist. The style, the router flow and the rest of the core strip are later PRs.
- No `analytics` block yet. The owner's sites use self-hosted OpenPanel, counted on the live host only, not PostHog. The `analytics` fact will route to an `analytics` block (OpenPanel, live host only); until it lands the PostHog core stays and blocks forward their events to it.
- `--update` diffs block source between two cleanstarter commits; an app that edited the applied code merges by hand.
- A block's tests run in jsdom only. A visual or browser check is a manual Verify step.
- The block's `src/` imports `@cleanstarter/*`; a renamed app needs the scope rewritten on apply.
