---
name: add-block
description: Add a block from mertbuilds/cleanstarter (a reusable site piece with code, copy and tests) to this app, or update an applied one. Use when the user says '/add-block <name>', 'add the <name> block', 'update the <name> block', or asks for a pattern that exists in the mertbuilds/cleanstarter blocks/ folder.
---

# add-block

`/add-block <name>` applies a block. `/add-block <name> --update` re-applies a newer version.

## Source

Blocks live in the `blocks/` folder of mertbuilds/cleanstarter. An app keeps no copy.

- When `git remote get-url origin` is mertbuilds/cleanstarter, read `blocks/` in place.
- Anywhere else, take a fresh clone every time and note its commit. The repo is private: clone over ssh with a key that has access to it.

```sh
dir=$(mktemp -d) && git clone --filter=blob:none git@github.com:mertbuilds/cleanstarter.git "$dir/blocks-source"
git -C "$dir/blocks-source" rev-parse --short HEAD
```

Below, `<source>` is that clone (`$dir/blocks-source`, with the path written out: shell variables do not carry between commands).

## Apply

1. Read `docs/product.md`. Create it from the format in `<source>/blocks/facts.md` when it is missing. Stop if the block is already listed (use `--update`).
2. Read `<source>/blocks/facts.md`, then the block's `block.md` and `questions.md`. Check that each required `core:<name>` piece exists, then apply each required block that is not listed yet, first.
3. Check `needs-when` against the facts. Ask the missing router facts first (`audience.locale` among them on a new site), together. When `needs-when` does not hold, say so and ask whether to go on.
4. Ask each fact the block needs that `docs/product.md` does not answer, with AskUserQuestion. Related questions go together, up to 4 in one call. Put the default (from `questions.md` or `facts.md`) first as the recommended option. Never ask a fact that is already answered: in `docs/product.md`, or said by the owner in this conversation.
5. Write the answers into the Facts table of `docs/product.md` (`Asked by`: the block, or `router`).
6. Follow the block's Apply steps. Adapt the code to the app (import scope, its existing links, its analytics); keep the block's behaviour and tests.
7. Stage the new files (`git add <paths>`; some checks read tracked files only). Run the block's Verify steps, then the repo checks: `pnpm typecheck`, `pnpm build`, `pnpm lint`, `pnpm format:check`, `pnpm knip`, `pnpm test`. Fix what fails.
8. Check the pages in a browser, whatever the block: at 1280x800 and at 390x844, a page with little content (the landing page, a form page) does not scroll (`document.documentElement.scrollHeight <= innerHeight`), and the console has no errors. Use ego-browser, the owner's browser tool, against `pnpm dev`, or the same checks in the e2e smoke (Playwright) when the app has one. Fix what fails.
9. Add the row to the Blocks table: name, `version`, `mertbuilds/cleanstarter@<commit>`, date.

## --update

1. Read the applied version and commit from `docs/product.md`, and the new `version` from `<source>/blocks/<name>/block.md`. Stop if they match.
2. Read the Update notes between them, and `git -C <source> diff <old commit> HEAD -- blocks/<name>`.
3. Bring that diff into the app's copy of the code, keeping the app's own edits. Ask the new facts, if any.
4. Verify as in Apply steps 7 and 8, then update the row: version, `mertbuilds/cleanstarter@<commit>`, date.

## Harvest

When the owner asks for a pattern that has no block and was asked for before (in this app or another), offer to make it a block in mertbuilds/cleanstarter, following its `blocks/README.md` (Harvest). Before building it:

1. Search the owner's repos under `~/code` for an existing version of the pattern: grep its key terms (the command is in `blocks/README.md`). When an agent memory file points to the owner's mertbuilds/cleanstarter learnings list, check it for where the pattern already works.
2. Read every version found, fully. Take the best one as the base and merge in what the others do better. Write from scratch only when none exists.
3. Say which repo and files the block came from, to the owner and in the first line of the block's `## Update notes`.
