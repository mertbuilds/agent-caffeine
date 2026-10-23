# 2. Release and build keys, one per job

Date: 2026-10-21. Status: accepted.

## Context

The repository is public and releases run from two places: GitHub Actions (`.github/workflows/mac-release.yml`) and the owner's Mac (`scripts/release.sh`). The website build on Vercel needs the paid Suisse Intl font files, which cannot be in a public repository.

Cloudflare R2 tokens that are limited to one bucket only work through the S3 API with their key pair, not through the Cloudflare REST API. Keys that sit in the login keychain cannot be used from scripted sessions, and they get lost when a Mac is migrated.

## Decision

Every job gets its own key, limited to the one thing it needs:

| Job | Key | Scope |
|---|---|---|
| Upload a release (GitHub Actions) | R2 S3 key pair | Object read and write, release bucket only |
| Upload a release (the Mac) | its own R2 S3 key pair | Object read and write, release bucket only |
| Fonts in the production build (Vercel) | R2 S3 key pair | Object read, fonts bucket only |
| Fonts in preview builds (Vercel) | its own R2 S3 key pair | Object read, fonts bucket only |
| Notarization | App Store Connect API key | Developer role |
| Update the Homebrew cask | fine-grained GitHub token | Contents read and write, `mertbuilds/homebrew-tap` only |

- GitHub Actions secrets live in the `mac-release` environment, which only `main` can use. Names are listed in README.md, "Release". The bucket name is a secret too, so it stays out of public logs.
- On the Mac, `~/.config/agent-caffeine/release.env` (mode 600) holds the Mac's keys and points to the Sparkle and notary key files next to it. `release.sh` reads it before it picks its modes, so a local release needs no `cf` login and no keychain item.
- Uploads go through `curl --aws-sigv4`, with the key pair on stdin. Checks of a new file go to the bucket URL, never to caffeinagent.com, because Cloudflare caches a 404 there for hours.

## Consequences

- Revoking one key breaks one job, and the others keep working.
- Rotating a key means one Cloudflare, Apple or GitHub token page plus one secret update. No key is shared between products.
- The Sparkle private key and the Developer ID certificate are the only keys that are the same in both release paths, because every copy of the app checks updates against that Sparkle key.
