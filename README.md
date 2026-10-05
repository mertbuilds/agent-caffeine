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

## Releases and updates

The app updates itself with [Sparkle](https://sparkle-project.org). It reads the feed at `https://caffeinagent.com/mac/appcast.xml` once a day, and from "Check for updates…" in the menu and in Preferences. Debug builds never check.

- `scripts/release.sh` is the only way to publish a release. It builds, signs, notarizes, writes the dmg, signs it for Sparkle, adds it to the appcast, uploads the dmg, `appcast.xml` and `latest.json` to `mac/` in the private R2 bucket the site serves (named in `~/.config/agent-caffeine/release.env`), and publishes the dmg to Polar. `--dry-run` does everything local and uploads, notarizes and publishes nothing. The header of the script lists the one-time setup.
- Updates are signed with the EdDSA key in the login keychain under the account `agent-caffeine`. Its public half is `SUPublicEDKey` in `project.yml`. Every Sparkle tool call passes `--account agent-caffeine`.
- Run the script from a local Terminal: the keychain refuses SSH and scripted sessions.
- Third-party licenses are in `THIRD_PARTY_NOTICES.md` and `Resources/Licenses/`, both bundled into the app.

## License keys

The app runs fully for 7 days from its first launch. After that it keeps the Mac awake only with a license key, sold on Polar. One key runs on one Mac (one Polar activation). The app activates, validates and deactivates keys through Polar's public customer portal endpoints, sandbox in Debug and production in Release (`Caffeinagent/License/LicenseConfig.swift`). The key, its activation id and the trial clock live in the login Keychain (service `com.caffeinagent.app.license`, `.debug` appended in Debug builds). The trial start, the latest time seen and the date of the last successful check are mirrored in `UserDefaults` in case the Keychain cannot be read; the key and the activation id are not. A licensed Mac stays licensed offline for 30 days after its last successful check.

## Roadmap

- [x] Phase 1: AC-only sleep prevention + Claude Code jsonl detector + CLI process detector + menu bar UI + preferences
- [x] Phase 2: battery override through a sudoers entry for `pmset -b disablesleep`
- [ ] Phase 3: launch-at-login, history log of awake periods, notification on state change
