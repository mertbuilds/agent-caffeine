# agent caffeine

> The brand is `agent caffeine`, always lowercase, also at the start of
> a sentence. Every user-visible string uses it: the app, the dmg and the
> site. `caffeinagent` is the name of the repo, the binary, the bundle id
> and the domain (caffeinagent.com), and the Xcode target and source
> folder are `Caffeinagent`. Users never see those names as the brand.

macOS menu bar app that keeps your Mac awake while AI coding agents work. By default it releases sleep prevention when agents are idle or waiting for your input, so the Mac can nap when it's safe to.

## What it does

- Finds the agents that run on the Mac from the process table and a built-in catalog (Claude Code, Codex, opencode, Antigravity and about 45 more). Preferences has one rule per agent (automatic, always counts as working while open, ignore) and a list for process names of tools that are not in the catalog.
- Reads what each agent says about itself where it can: Claude Code's session state files and Codex's session logs give working, waiting for you, or idle. Other agents are judged by signs of work: a running command, a background task, a power assertion of their own, writes to their session files and, as weak evidence, processor use.
- Three modes, picked in the menu or in Preferences:
  - Always: keeps the Mac awake until you switch it off, agents or not.
  - While an agent is open: keeps the Mac awake while any agent is detected, working or idle.
  - While an agent is working (default): keeps the Mac awake while an agent works, for a short time after it finishes (2 minutes by default), and for a while when it waits for you (5 minutes by default).
- While keeping the Mac awake it holds `PreventUserIdleSystemSleep` and `PreventSystemSleep` assertions, and releases them as soon as the mode no longer calls for them. The assertions carry a 2 minute timeout that every decision renews, so a hung app cannot keep the Mac awake.
- Lets the Mac sleep when the battery is low (20 percent by default) or the Mac gets too hot, and says so in a notification.
- Surfaces state in the menu bar with a robot-head icon: solid and smiling when keeping the Mac awake, outlined with closed eyes when not. The menu names what keeps the Mac awake and lists each agent with its state and the reason.

The detection code is in `Caffeinagent/Detection/`, and the research behind it in `docs/research/`. `caffeinagent --lab-record <label>` records what the engine sees without starting the app (see `Caffeinagent/LabCommand.swift`).

## Lid closed on battery

`kIOPMAssertionTypePreventSystemSleep` keeps the Mac awake with the **lid closed only on AC power**. On battery, macOS sleeps on lid close regardless, and an assertion alone cannot override that. Only the system-wide `SleepDisabled` setting does, and it needs root.

The app sets it through a small root helper (`CaffeinagentHelper/`), registered with `SMAppService` from Preferences > Lid closed and approved once in System Settings > General > Login Items. The helper is offered only when the app runs from `/Applications`. It takes two booleans over XPC from the signed app and nothing else. The app sets the flag together with the power assertions, also on AC, so unplugging with the lid closed does not race it, and sends a heartbeat. The helper clears the flag when the heartbeats stop, at its own start, and never clears a flag it did not set. `SleepDisabled` also blocks the kernel's low-battery and thermal sleep, which is why the app watches both itself.

Builds before the helper used a sudoers entry for `pmset -b disablesleep`. The app clears a flag such a build left on at first launch, and Preferences offers to remove the entry.

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

The app updates itself with [Sparkle](https://sparkle-project.org). It reads the feed at `https://caffeinagent.com/mac/appcast.xml` once a day, and from "Check for updates…" in Preferences. Debug builds never check.

- `scripts/release.sh` is the only way to publish a release. It builds, signs, notarizes, writes the dmg, signs it for Sparkle, adds it to the appcast, uploads the dmg, `appcast.xml` and `latest.json` to `mac/` in the private R2 bucket the site serves (named in `~/.config/agent-caffeine/release.env`), and publishes the dmg to Polar. `--dry-run` does everything local and uploads, notarizes and publishes nothing. The header of the script lists the one-time setup.
- Updates are signed with the EdDSA key in the login keychain under the account `agent-caffeine`. Its public half is `SUPublicEDKey` in `project.yml`. Every Sparkle tool call passes `--account agent-caffeine`.
- Run the script from a local Terminal: the keychain refuses SSH and scripted sessions.
- Third-party licenses are in `THIRD_PARTY_NOTICES.md` and `Resources/Licenses/`, both bundled into the app.

## License keys

The app runs fully for 7 days from its first launch. After that it keeps the Mac awake only with a license key, sold on Polar. One key runs on one Mac (one Polar activation). The app activates, validates and deactivates keys through Polar's public customer portal endpoints, sandbox in Debug and production in Release (`Caffeinagent/License/LicenseConfig.swift`). The key, its activation id and the trial clock live in the login Keychain (service `com.caffeinagent.app.license`, `.debug` appended in Debug builds). The trial start, the latest time seen and the date of the last successful check are mirrored in `UserDefaults` in case the Keychain cannot be read; the key and the activation id are not. A licensed Mac stays licensed offline for 30 days after its last successful check.

## Roadmap

- [x] Phase 1: AC-only sleep prevention + Claude Code jsonl detector + CLI process detector + menu bar UI + preferences
- [x] Phase 2: battery override through a sudoers entry for `pmset -b disablesleep`
- [x] Phase 3: detection engine with an agent catalog, root helper for the lid-closed flag, battery and heat safety stops
- [ ] Phase 4: onboarding window, agent hooks, remote access detection, launch-at-login
