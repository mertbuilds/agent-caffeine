# agent caffeine

> The brand is `agent caffeine`, always lowercase, also at the start of
> a sentence. Every user-visible string uses it: the app, the dmg and the
> site. `caffeinagent` is the name of the repo, the binary, the bundle id
> and the domain (caffeinagent.com), and the Xcode target and source
> folder are `Caffeinagent`. Users never see those names as the brand.

macOS menu bar app that keeps your Mac awake while AI coding agents work. By default it releases sleep prevention when agents are idle or waiting for your input, so the Mac can nap when it's safe to.

## What it does

- Watches `~/.claude/projects/*.jsonl` to detect Claude Code session activity (active turn vs. waiting for input vs. idle).
- Watches a user-editable CLI allowlist (`codex`, `cursor-agent`, `gemini`, …). A matched process counts as working while it and its child processes use at least 3% of one core, plus a two-minute grace period; otherwise it is waiting for input.
- Three modes, picked in the menu or in Preferences:
  - Always: keeps the Mac awake until you switch it off, agents or not.
  - While an agent is open: keeps the Mac awake while any agent is detected, working or idle.
  - While an agent is working (default): keeps the Mac awake only while an agent is working.
- While keeping the Mac awake it holds `PreventUserIdleSystemSleep` and `PreventSystemSleep` assertions, and releases them as soon as the mode no longer calls for them.
- Surfaces state in the menu bar with a coffee-cup icon: filled when keeping the Mac awake, empty when not.

## macOS limit

`kIOPMAssertionTypePreventSystemSleep` keeps the Mac awake with the **lid closed only on AC power**. On battery, macOS clamshell-sleeps regardless, and an assertion alone can't override that. The optional battery override works around it: install the sudoers entry from Preferences, and while the app keeps the Mac awake on battery it runs `sudo pmset -b disablesleep 1`, then `0` when it stops or quits. On Apple silicon this does not always prevent clamshell sleep.

## Build

Requires Xcode 16+, macOS 13+ deployment target.

```bash
brew install xcodegen          # one-time
xcodegen generate              # regenerate Xcode project from project.yml
xcodebuild -project Caffeinagent.xcodeproj -scheme Caffeinagent -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/caffeinagent.app
```

Run the unit tests with `xcodebuild test -project Caffeinagent.xcodeproj -scheme Caffeinagent -destination 'platform=macOS'`.

## Roadmap

- [x] Phase 1: AC-only sleep prevention + Claude Code jsonl detector + CLI process detector + menu bar UI + preferences
- [x] Phase 2: battery override through a sudoers entry for `pmset -b disablesleep`
- [ ] Phase 3: launch-at-login, history log of awake periods, notification on state change
