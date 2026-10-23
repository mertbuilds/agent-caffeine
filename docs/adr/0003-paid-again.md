# 3. Paid again

Date: 2026-10-23. Status: accepted. Supersedes the decision of 2026-10-12 to make the app free and open source (commits 2e20f12 and ac2c1c6), and [1. Support through GitHub Sponsors](0001-support-through-github-sponsors.md).

## Context

With 1.1.0 Agent Caffeine became free and open source under the AGPL, and voluntary support went through GitHub Sponsors. The owner, Mert Düzgün, is the sole author and holds the copyright of all of the code, so he can choose another license for new versions. He decided to sell the app again.

## Decision

- One product on Polar (organization `mertbuilds`): a lifetime key for $14, one payment. A launch price of $9 is an automatic discount at checkout. The site shows the price, and the app only opens the checkout link.
- A key runs on 3 Macs. Keys have the prefix `AGENTCAF`. The product has only this license key benefit: buyers download the app from caffeinagent.com, and a release publishes nothing to Polar.
- A key runs every build released within 365 days of its purchase, for ever. A build released later needs a new key. Sparkle does not offer such a build to a Mac with that key, and Settings says that its updates ended. The build carries its release date in Info.plist (`ACReleaseDate`, set by `scripts/release.sh`), and the purchase date is the `created_at` of the key from Polar.
- A 7-day trial from the first launch of a paid build. People who come from the free 1.1.x builds or the paid 1.0.x builds get a full trial: the trial is stored under new names.
- Keys of the earlier products (1 Mac and 3 Macs) keep working, and follow the same year of updates from their purchase.
- The repository is private. New versions are proprietary, with all rights reserved. Third-party notices stay, and so does the MIT license for the files the app writes into agent folders.
- GitHub Sponsors ends for this app: the links in the app and `.github/FUNDING.yml` are gone.

## Consequences

- The license code of 1.0.x is back (`Caffeinagent/License/`), with `UpdateWindow` for the year of updates. The clean-up of the free version that deleted the license record and the trial settings is gone.
- The app checks keys with Polar again. Settings > About says so, and the privacy page of the site has to say so too.
- Versions released under the AGPL stay under the AGPL for the people who have them. New versions are not.
- A refunded buyer whose old activation still counts on Polar may need to free it in the customer portal before the key activates on the same Mac again.
