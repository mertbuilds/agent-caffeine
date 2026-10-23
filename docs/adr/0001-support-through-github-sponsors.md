# 1. Support through GitHub Sponsors

Date: 2026-10-21. Status: superseded by [3. Paid again](0003-paid-again.md).

## Context

Agent Caffeine went free and open source (AGPL-3.0-only) with 1.1.0. Buyers of 1.0.x were refunded, and their license keys keep working. People can still choose to give money. We needed one place for that.

We tried a pay-what-you-want product on Polar first. Polar is the merchant of record and handles tax, but it is a shop: checkout pages, receipts, and products to manage. GitHub Sponsors sits next to the source code, takes one-time and monthly support, and needs nothing from us per payment.

## Decision

Voluntary support goes through GitHub Sponsors only, at https://github.com/sponsors/mertbuilds.

- The website has a support section on the home page (`/#support`) with a header link. `/support` redirects there, because the app and older links point to it.
- The app's About tab opens GitHub Sponsors directly (`AppLinks.support`).
- `.github/FUNDING.yml` shows the Sponsor button on the repository.
- Support unlocks nothing. Every copy of the app is the same.

## Consequences

- The Polar products for Agent Caffeine are archived. Polar stays only as the record of the 1.0.x sales and refunds, so the privacy page and terms mention Polar for purchases before 1.1.0.
- GitHub shares only a sponsor's username, public profile and amount with us, and an email address only if the sponsor allows it. The privacy page says so.
