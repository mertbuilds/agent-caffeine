# agent caffeine

> The brand is `agent caffeine`, always lowercase, also at the start of
> a sentence. Every user-visible string uses it: the app, the dmg and the
> site. `caffeinagent` is the name of the repo, the binary, the bundle id
> and the domain (caffeinagent.com), and the Xcode target and source
> folder are `Caffeinagent`. Users never see those names as the brand.

macOS menu bar app that keeps your Mac awake while AI coding agents work. By default it releases sleep prevention when agents are idle or waiting for your input, so the Mac can nap when it's safe to.

## What it does

- Finds the agents that run on the Mac from the process table and a built-in catalog (Claude Code, Codex, opencode, Antigravity and about 45 more). Preferences has one rule per agent (automatic, always counts as working, ignore) and a list for process names of tools that are not in the catalog.
- Reads what each agent says about itself where it can: Claude Code's session state files and Codex's session logs give working, waiting for you, or idle. Other agents are judged by signs of work: a running command, a background task, a power assertion of their own, writes to their session files and, as weak evidence, processor use.
- Takes the state from an agent's hooks when you switch them on (see Hooks below). A fresh hook state comes before everything else.
- Three modes, picked in the menu or in Preferences:
  - Always: keeps the Mac awake until you switch it off, agents or not.
  - While an agent is open: keeps the Mac awake while any agent is detected, working or idle.
  - While an agent is working (default): keeps the Mac awake while an agent works, for a short time after it finishes (2 minutes by default), and for a while when it waits for you (5 minutes by default).
- While keeping the Mac awake it holds `PreventUserIdleSystemSleep` and `PreventSystemSleep` assertions, and releases them as soon as the mode no longer calls for them. The assertions carry a 2 minute timeout that every decision renews, so a hung app cannot keep the Mac awake.
- Lets the Mac sleep when the battery is low (20 percent by default) or the Mac gets too hot, and says so in a notification.
- Surfaces state in the menu bar with a small version of the robot of the app icon, in the same pose as the robot in the menu: a solid head with smiling eyes when keeping the Mac awake, round eyes while an agent is waiting for you, an outline with closed eyes when the Mac can sleep or agent caffeine is paused, dimmed when off, and red crosses for eyes after a safety stop. The menu names what keeps the Mac awake and lists each agent with its state and the reason.
- "Show agent caffeine in the menu bar" (Preferences > General, on by default) hides the icon. The app keeps your Mac awake the same way without it. To open Preferences again, open agent caffeine from Applications or Spotlight. While the icon is hidden, a notification says when the trial has ended, the helper was switched off or the helper cannot be reached.
- Pause: "Pause for 30 minutes", "Pause for 1 hour" or "Pause until tomorrow" (06:00, or 8 hours when the morning is less than 4 hours away), from the pause button next to the switch or from the gear menu. While paused agent caffeine holds nothing and clears the lid closed setting, as if it were off, and starts again by itself. The end is a time on the clock ("Paused until 15:30") and is saved, so it lasts over a restart of the app, and the time the Mac sleeps counts: a Mac that slept past the end wakes with the pause over. Switching agent caffeine off ends a pause, and "Resume" ends it at once. The rule is `Caffeinagent/Detection/Pause.swift`.
- Keyboard shortcuts that work in every app (Preferences > General > Keyboard shortcuts): "Turn agent caffeine on or off", which is the switch and ends a pause, and "Pause for 1 hour". None is set until you record one. They are registered with Carbon's `RegisterEventHotKey`, which needs no Accessibility permission. A shortcut needs Command, Control or Option, and one that macOS uses is refused (`Caffeinagent/Shortcut/`).

- On power, stays awake while a tool's phone access is on, also when no agent works (see Phone access below).

The detection code is in `Caffeinagent/Detection/`, and the research behind it in `docs/research/`. `caffeinagent --lab-record <label>` records what the engine sees without starting the app (see `Caffeinagent/LabCommand.swift`). The app binary starts the app only without arguments: the lab commands and `--smoke-test` (see Before a release) are the only arguments it takes, and it refuses any other.

## Hooks

Some agents can run a command when their state changes. With hooks on, an agent tells agent caffeine when it works, waits for you or is done, so nothing has to be inferred. Hooks are off until you switch them on, per agent, in Preferences > Agents > Better detection or in the setup window.

- Supported: Claude Code and Codex (adds "waiting for your permission"), Droid and opencode (adds working, waiting and done). `Caffeinagent/Detection/Hooks/HookCatalog.swift` holds the list, what each entry was confirmed by, and the agents that are left out and why.
- Switching hooks on adds a few lines to the agent's own config file (`~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.factory/settings.json`), or writes one plugin file for opencode. The rest of the file stays as it is, a backup is kept next to it, and switching hooks off removes exactly those lines again.
- The lines run `CaffeinagentHook`, a small command inside the app in `/Applications`, never the app itself. It reads the event, writes one small state file per agent process to `~/Library/Application Support/com.caffeinagent.app/hooks/`, prints nothing and always exits 0. It keeps the state and the name of the event, and nothing you or the agent typed. The app does not have to run, and the lines do nothing when the app is gone.
- Hooks need the app in `/Applications`, because the lines point there.

## Setup window

The first launch opens a setup window once. It names the agents it found, offers the hooks of the agents that have them, and offers the lid closed helper on a Mac with a battery. Every step can be skipped, and the app works the same while the window is open. Everything in it is also in Preferences.

## Phone access

Claude Code Remote Control lets you work with a session on this Mac from a phone or the web, and that only works while the Mac is awake. With "Stay awake for phone access while plugged in" (Preferences > General, on by default), the Mac stays awake on power while Remote Control is on, also when no agent works. The menu then says "Phone access is on". On battery this does not hold the Mac awake.

Remote Control counts as on for a `claude remote-control` server, for a session started with `--remote-control` or `--rc`, and for every interactive session when `remoteControlAtStartup` is true in `~/.claude/settings.json`. A session that turns it on later with `/remote-control` is not seen. No other tool has a detector yet (`Caffeinagent/Detection/RemoteAccessDetector.swift`).

## Lid closed on battery

`kIOPMAssertionTypePreventSystemSleep` keeps the Mac awake with the **lid closed only on AC power**. On battery, macOS sleeps on lid close regardless, and an assertion alone cannot override that. Only the system-wide `SleepDisabled` setting does, and it needs root.

The app sets it through a small root helper (`CaffeinagentHelper/`), registered with `SMAppService` from Preferences > Lid closed and approved once in System Settings > General > Login Items. The helper is offered only when the app runs from `/Applications`. It takes two booleans over XPC from the signed app and nothing else. The app sets the flag together with the power assertions, also on AC, so unplugging with the lid closed does not race it, and sends a heartbeat. The helper clears the flag when the heartbeats stop, at its own start, and when launchd stops it, and never clears a flag it did not set. `SleepDisabled` also blocks the kernel's low-battery and thermal sleep, which is why the app watches both itself.

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

## Before a release

Run `scripts/smoke-test.sh`. The unit tests never start the app, so they pass on a build that hangs at launch. The smoke test builds the app and starts it for 8 seconds as `caffeinagent --smoke-test 8`: the real scenes, the real aggregator and the real engine, with no power assertion, helper, Keychain, Polar, Sparkle or notification behind them, and with settings of its own, so it is safe next to the copy you use. It hides and shows the icon, opens Preferences once, and fails when the main thread stalls, the app uses more than 15 percent of a core, the scenes are worked out more than 50 times per second, the menu bar has no icon or the engine takes no sample. It prints what it measured as one line of JSON, then PASS or FAIL. `scripts/smoke-test.sh --app <path>` tests a bundle that is built already, and `scripts/release.sh` runs it on the signed app and stops when it fails, also with `--dry-run`.

## License keys

The app runs fully for 7 days from its first launch. After that it keeps the Mac awake only with a license key, sold on Polar. One key runs on one Mac (one Polar activation). The app activates, validates and deactivates keys through Polar's public customer portal endpoints, sandbox in Debug and production in Release (`Caffeinagent/License/LicenseConfig.swift`). The key, its activation id and the trial clock live in the login Keychain (service `com.caffeinagent.app.license`, `.debug` appended in Debug builds). The trial start, the latest time seen and the date of the last successful check are mirrored in `UserDefaults` in case the Keychain cannot be read; the key and the activation id are not. A licensed Mac stays licensed offline for 30 days after its last successful check.

## Roadmap

- [x] Phase 1: AC-only sleep prevention + Claude Code jsonl detector + CLI process detector + menu bar UI + preferences
- [x] Phase 2: battery override through a sudoers entry for `pmset -b disablesleep`
- [x] Phase 3: detection engine with an agent catalog, root helper for the lid-closed flag, battery and heat safety stops
- [x] Phase 4: setup window, agent hooks, phone access detection
- [ ] Phase 5: launch-at-login
