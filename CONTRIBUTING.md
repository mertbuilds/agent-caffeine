# Contributing

Issues and pull requests are welcome. For a larger change, open an issue first, so nobody does work that cannot be merged.

## Build and run

You need a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and is not in the repository.

```bash
xcodegen generate
xcodebuild -project Caffeinagent.xcodeproj -scheme Caffeinagent -configuration Debug build
```

A Debug build is signed ad hoc. It builds and runs with no Apple account. Two things do not work in it, by design:

- The helper refuses it, so the Mac does not stay awake with the lid closed on battery, and "Wake for jobs" sets no wake time.
- The updater never starts.

## Tests

```bash
xcodebuild test -project Caffeinagent.xcodeproj -scheme Caffeinagent -destination "platform=macOS"
```

The unit tests never start the app. They compile the logic files directly, so they touch no power setting, no helper and no Keychain.

- `scripts/smoke-test.sh` builds the app and starts it for a few seconds beside an installed copy, and checks that it does not hang. Run it after a change to the app's scenes or its start.
- `scripts/actest` is the test runner for the real app on a real Mac. Its own tests run with `cd scripts/actest && python3 -m unittest discover -s selftest -t .`. See `scripts/actest/README.md`.

## Style

- Plain, simple English in comments, commit messages and every text people read. No em dashes.
- The brand is written "Agent Caffeine".
- A change of behaviour comes with a test.
- A change of the text of the skill (`skills/agent-caffeine/SKILL.md`) needs a new `SkillCatalog.version` and its digest in `SkillTextTests`. The texts of released plugin files in `HookPluginHistory` never change.

## Sign-off

Your contribution is under the license of this repository, AGPL-3.0-only (see [LICENSE](LICENSE)). The small files that the app writes into agent folders are also under the MIT license (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).

Every commit needs a sign-off line. It says that you agree to the [Developer Certificate of Origin](https://developercertificate.org), version 1.1: you wrote the change or have the right to give it under this license.

```bash
git commit -s
```

This adds the line `Signed-off-by: Your Name <you@example.com>` to the commit message.

## A fork cannot use the owner's keys

The release of Agent Caffeine is signed with the owner's Developer ID and its updates with the owner's Sparkle key. Neither is in the repository. A changed version that you give to other people must also have another name and another icon (see [TRADEMARKS.md](TRADEMARKS.md)). Change these values before you release a fork:

| What | Where | Why |
| --- | --- | --- |
| The team id `3HGP3W3TLD` in the code signing requirement of the helper | `teamID` in `Caffeinagent/Power/SleepFlagHelperProtocol.swift` | The helper and the app accept each other only when this team signed both. With the owner's id your build and its helper refuse each other. This check is the security boundary of the root helper: keep it strict. |
| The team id for release signing | `DEVELOPMENT_TEAM` in `project.yml`, `TEAM_ID` in `scripts/release.sh` | You need your own Developer ID Application certificate. |
| The notary profile `caffeinagent-notary` | `NOTARY_PROFILE` in `scripts/release.sh` | Your own `notarytool` keychain profile. |
| The bundle ids `com.caffeinagent.app`, `.helper`, `.hook`, `.cli` | `bundleIdPrefix` and each `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, `appBundleID` and `label` in `SleepFlagHelperProtocol.swift`, `CaffeinagentHelper/com.caffeinagent.app.helper.plist`, and the sources that name `com.caffeinagent.app` for support folders, settings and logs | Two apps with the same helper label cannot both register the launch daemon, and they would share settings. |
| The update feed `SUFeedURL` | `project.yml` | With the owner's feed your users would be offered the owner's build, and Sparkle would replace your fork with it. |
| The update key `SUPublicEDKey`, and the keychain account `agent-caffeine` of its private half | `project.yml`, `SPARKLE_ACCOUNT` in `scripts/release.sh` | You cannot sign an update for the owner's public key. Make your own EdDSA key pair. |
| The R2 bucket and the addresses `https://files.caffeinagent.com` and `https://caffeinagent.com/mac` | `R2_BUCKET` in `~/.config/agent-caffeine/release.env`, `SITE_URL` in `scripts/release.sh` | Your own host for the dmg, `appcast.xml` and `latest.json`. |
| The links in the app | `Caffeinagent/Models/AppLinks.swift`, `builderURL` in `Caffeinagent/UI/PreferencesView.swift` | Your own help, contact, source code and support pages. The link to the source code must stay a link to the source of the version you give out. |
