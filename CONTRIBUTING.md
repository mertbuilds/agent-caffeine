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

## Release

Only the owner releases. `scripts/release.sh` is the one release path. It builds, signs, notarizes and staples the app, makes the dmg, signs the update for Sparkle and writes `appcast.xml` and `latest.json`. Then it uploads the dmg first and the two feeds last to the bucket, under `mac/`, and checks on `https://files.caffeinagent.com/mac/` that the dmg has the same size and sha256 and that the appcast lists the build. Each upload is live at once.

The workflow `.github/workflows/mac-release.yml` runs the same script on GitHub Actions:

1. Write the notes in `release-notes/<version>.md`.
2. Raise `CURRENT_PROJECT_VERSION` in `project.yml` (and `MARKETING_VERSION` for a new version), and push to `main`.
3. The job `detect` compares the build with the highest build in `https://files.caffeinagent.com/mac/appcast.xml`. When it is higher, the job `release` waits for the approval of the environment `mac-release`.
4. Before you approve, you can start a dry run: Actions, "Mac release", "Run workflow" on `main`, with "dry run" on (the default). It does everything but the uploads, notarization included, and keeps the dmg, `appcast.xml` and `latest.json` as an artifact of the run for 7 days.
5. Approve the real run. After the upload it writes the tag `v<version>` and a GitHub release with the notes, the link to the dmg and its sha256. With `HOMEBREW_TAP_TOKEN` set it also bumps the cask in `mertbuilds/homebrew-tap` with that repository's `scripts/bump-cask.sh`.

"Run workflow" with "dry run" off is a real release, started by hand. Both kinds of run start only from `main`. A build that is not above the published one is never released.

The environment `mac-release` needs a required reviewer, so that no run gets the keys without the owner's approval. It holds these secrets:

| Secret | What |
| --- | --- |
| `MAC_DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate and its private key, as a .p12 file in base64 |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | The password of that .p12 file |
| `MAC_NOTARY_API_KEY_P8_BASE64` | An App Store Connect API key for the notary service, the .p8 file in base64 |
| `MAC_NOTARY_API_KEY_ID` | The id of that key |
| `MAC_NOTARY_API_ISSUER_ID` | The issuer id of that key |
| `MAC_SPARKLE_ED25519_PRIVATE_KEY` | The Sparkle private key of the account `agent-caffeine`, the text of the file that `generate_keys --account agent-caffeine -x <file>` writes |
| `MAC_R2_S3_ACCESS_KEY_ID` | The S3 access key id of an R2 API token that can read and write the bucket |
| `MAC_R2_S3_SECRET_ACCESS_KEY` | The S3 secret access key of that token |
| `MAC_CLOUDFLARE_ACCOUNT_ID` | The Cloudflare account that holds the bucket |
| `HOMEBREW_TAP_TOKEN` | Optional. A token that can push to `mertbuilds/homebrew-tap`. Without it the cask is not bumped |

and the variable `MAC_R2_BUCKET`, the name of the bucket. A dry run never gets the R2 secrets or the tap token.

On the Mac, `scripts/release.sh` works as before, with the keys in the login keychain, `cf` for the bucket and the bucket name in `~/.config/agent-caffeine/release.env`. `scripts/release.sh --dry-run` builds and signs but notarizes and uploads nothing. The header of the script lists the environment variables the workflow sets in their place.

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
| The notary profile `caffeinagent-notary` | `NOTARY_PROFILE` in `scripts/release.sh` | Your own `notarytool` keychain profile, or your own API key in the workflow's secrets. |
| The bundle ids `com.caffeinagent.app`, `.helper`, `.hook`, `.cli` | `bundleIdPrefix` and each `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, `appBundleID` and `label` in `SleepFlagHelperProtocol.swift`, `CaffeinagentHelper/com.caffeinagent.app.helper.plist`, and the sources that name `com.caffeinagent.app` for support folders, settings and logs | Two apps with the same helper label cannot both register the launch daemon, and they would share settings. |
| The update feed `SUFeedURL` | `project.yml` | With the owner's feed your users would be offered the owner's build, and Sparkle would replace your fork with it. |
| The update key `SUPublicEDKey`, and the keychain account `agent-caffeine` of its private half | `project.yml`, `SPARKLE_ACCOUNT` in `scripts/release.sh` | You cannot sign an update for the owner's public key. Make your own EdDSA key pair. |
| The R2 bucket and the addresses `https://files.caffeinagent.com` and `https://caffeinagent.com/mac` | `R2_BUCKET` in `~/.config/agent-caffeine/release.env` (or the variable `MAC_R2_BUCKET`), `BUCKET_URL` and `SITE_URL` in `scripts/release.sh`, `APPCAST_URL` in `scripts/release-request.sh`, the url checks in `.github/workflows/mac-release.yml` | Your own host for the dmg, `appcast.xml` and `latest.json`. |
| The Homebrew tap `mertbuilds/homebrew-tap` | `.github/workflows/mac-release.yml` | Leave `HOMEBREW_TAP_TOKEN` unset, or point the workflow at your own tap. |
| The links in the app | `Caffeinagent/Models/AppLinks.swift`, `builderURL` in `Caffeinagent/UI/PreferencesView.swift` | Your own help, contact, source code and support pages. The link to the source code must stay a link to the source of the version you give out. |
