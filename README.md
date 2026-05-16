# caffeinagent

> the brand is fully lowercase: `caffeinagent`. user-visible strings,
> file paths, and the menu bar label all read as `caffeinagent`. the
> internal Xcode target / source folder keeps the capitalized
> `Caffeinagent` identifier purely as a build-system convention; nothing
> outside the toolchain sees it.

macOS menu bar app that keeps your Mac awake while AI coding agents are running. Releases sleep prevention when agents are idle or waiting for your input, so the Mac can nap when it's safe to.

## What it does

- Watches `~/.claude/projects/*.jsonl` to detect Claude Code session activity (active turn vs. waiting for input vs. idle).
- Watches a user-editable CLI allowlist (`codex`, `cursor-agent`, `gemini`, …) for non–Claude Code agents.
- Holds an `IOPMAssertionTypePreventSystemSleep` while any agent is `active`, releases as soon as everything goes `waitingForInput` or `idle`.
- Surfaces state in the menu bar with a coffee-cup icon: filled when keeping the Mac awake, empty when not.

## macOS limit

`kIOPMAssertionTypePreventSystemSleep` keeps the Mac awake with the **lid closed only on AC power**. On battery, macOS clamshell-sleeps regardless — this is enforced below userland by SMC and can't be overridden from a sandboxed app. A Phase 2 privileged helper that toggles `pmset -b disablesleep` can work around this; not yet implemented.

## Build

Requires Xcode 16+, macOS 14+ deployment target.

```bash
brew install xcodegen          # one-time
xcodegen generate              # regenerate Xcode project from project.yml
xcodebuild -project Caffeinagent.xcodeproj -scheme Caffeinagent -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/caffeinagent.app
```

## Roadmap

- [x] Phase 1: AC-only sleep prevention + Claude Code jsonl detector + CLI process detector + menu bar UI + preferences
- [ ] Phase 2: privileged helper (`SMAppService`) for `pmset disablesleep` battery override
- [ ] Phase 3: launch-at-login, history log of awake periods, notification on state change
