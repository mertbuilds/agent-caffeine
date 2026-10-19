---
title: "Amphetamine for Mac: closed-display mode and alternatives"
description: "What the free Amphetamine app does on a Mac, how its closed-display mode works, what Power Protect and Amphetamine Enhancer are, and when another tool fits."
date: "2026-10-08"
updated: "2026-10-12"
faq:
  - q: "Is Amphetamine for Mac free?"
    a: "Yes. Amphetamine is free on the Mac App Store. Its description says: \"No catch. Amphetamine is 100% free.\" It also lists \"No advertisements\" and \"No in-app purchases\"."
  - q: "Does Amphetamine keep a MacBook awake with the lid closed?"
    a: "Yes, its App Store description lists \"Keep your MacBook awake while its display/lid is closed\". During a session you choose to allow or prevent \"System sleep when built-in display is closed\". On Apple silicon laptops the developer offers a separate install named Power Protect for this mode."
  - q: "What is Amphetamine Enhancer?"
    a: "A helper app from the same developer, on GitHub under the MIT license. Its README says it \"adds a fail-safe for the closed-display mode feature found in Amphetamine 5.0+\" and lets Amphetamine use all running processes with Triggers. It is not on the App Store."
  - q: "Does Amphetamine work on Apple silicon Macs?"
    a: "The App Store version history speaks of Apple silicon Macs directly: the notes for versions 5.3.1 and 5.3.2 list a warning when Amphetamine runs using Rosetta, and Power Protect is described as \"only needed/available on Apple Silicon Mac laptops\"."
  - q: "What is the Mac command that does what Amphetamine does?"
    a: "`caffeinate`. It is built into macOS. `caffeinate -i` keeps the Mac awake until you press Ctrl+C, and `caffeinate -i -t 3600` keeps it awake for one hour."
---

Amphetamine is a free app for macOS that stops your Mac from sleeping. You get it from the Mac App Store, it sits in the menu bar, and you start a session with a click: until you stop it, for a set time, or until a time on the clock. It can also keep a MacBook awake with the lid closed, which it calls closed-display mode.

This guide says what the app does, what closed-display mode needs today, and which other tool fits when Amphetamine is more or less than you need. We make one of those other tools, so we quote Amphetamine's own pages and link them.

## What Amphetamine does

Amphetamine is made by William Gustafson. His App Store page describes two ways to use it.

Sessions that you start yourself. From the menu you keep the Mac awake:

- "Indefinitely, for a specified amount of time, or until a specified time"
- "While a file is downloading"
- "While a specific app is running"

During a session you choose to allow or prevent display sleep, the screen saver, the lock of the screen, and "System sleep when built-in display is closed".

Triggers that start sessions for you. A Trigger is a rule. The page lists many, among them:

- "While an external display is connected"
- "While a specific app is running"
- "While your Mac's power adapter is connected or disconnected"
- "While your Mac is on a specific Wi-Fi network"
- "While your Mac's CPU is being utilized to a specific threshold"

It also has hot keys, AppleScript support, and an option to "Auto-end session if your Mac's battery is low".

## Price, version and macOS support

These are the facts on the App Store page on October 8, 2026:

| Fact | What the page says |
| --- | --- |
| Price | Free |
| In-app purchases | "No in-app purchases" |
| Newest version | 5.3.2, dated November 10, 2023 |
| Compatibility | "Requires macOS 10.13 or later" |
| Size | 6.7 MB |
| Privacy label | Diagnostics (crash data), not linked to you |

The description is plain about the price: "No catch. Amphetamine is 100% free." It also lists "No tracking" and "No data-harvesting".

The newest version is from 2023. The page does not say anything about the macOS versions that came after it, and we did not test Amphetamine on them for this guide, so we make no claim. If you are on a new macOS, install it and run the short test at the end of the next section.

## How closed-display mode works

A MacBook sleeps when you close the lid. Closed-display mode is a session in which Amphetamine prevents that sleep, so the Mac keeps running with the lid closed. You set it per session with the option "System sleep when built-in display is closed".

Two extra pieces exist around this mode. Both are separate downloads from the developer's GitHub account, not parts of the App Store app.

### Power Protect, for Apple silicon laptops

The version history explains it: "In Amphetamine 5.3, a Closed-Display Mode script was introduced to address an issue on Apple Silicon Macs where connecting or disconnecting your Mac laptop from an external power source could cause unexpected session behavior."

At first that script asked for Touch ID or an administrator's password each time. Since version 5.3.1 it can run without that, and the feature has a name: "This feature is now known as Power Protect and is only needed/available on Apple Silicon Mac laptops."

It is not built in. The notes say: "Power Protect is not included directly in Amphetamine and requires a separate download and installation." The [install page on GitHub](https://github.com/x74353/Amphetamine) has three steps:

1. Put the Power Protect script in the folder `~/Library/Application Scripts/com.if.Amphetamine/`.
2. Put the configuration file in `/private/etc/sudoers.d/`.
3. Run one `defaults write` command in Terminal, which the page gives you to copy.

The configuration file is a sudoers rule of two lines. It lets administrator accounts run `pmset -a disablesleep 1` and `pmset -a disablesleep 0` without a password. That is the same sleep setting that you can set by hand, as our guide on [how to keep a Mac awake with the lid closed](/blog/keep-mac-awake-lid-closed) shows. To remove both again, the version notes name the path: Amphetamine's menu bar icon, then **Feedback & Support**, then **Uninstall Scripts...**.

### Amphetamine Enhancer

[Amphetamine Enhancer](https://github.com/x74353/Amphetamine-Enhancer) is a helper app from the same developer. Its README describes it this way: "Amphetamine Enhancer is a helper application that enhances a couple of Amphetamine's features." It adds two things:

- "Adds a fail-safe for the closed-display mode feature found in Amphetamine 5.0+"
- "Gives Amphetamine 5.0+ the ability to use all running processes with Triggers and app-based sessions"

It is separate because apps on the Mac App Store are sandboxed, and the README says a sandboxed app cannot do these tasks. It is open source under the MIT license, and the README says that Apple notarized the release.

What the pages do not say:

- The README does not say that closed-display mode needs Enhancer. It calls it a fail-safe, so it is an extra.
- The README does not mention Apple silicon. The last commit in the repository is from February 18, 2020.
- Neither page says whether closed-display mode on battery needs one of these two pieces.

So on an Apple silicon laptop, Power Protect is the piece that Amphetamine's own notes point you to.

### Test it on your Mac

Because of the open points above, test closed-display mode before you rely on it. Start a session, then run this in Terminal:

```sh
while true; do date >> ~/awake.log; sleep 60; done
```

Close the lid for ten minutes, on the power source you plan to use. Open it and run `cat ~/awake.log`. One line per minute means that the Mac stayed awake. Press Ctrl+C to stop the loop.

## When Amphetamine is the better choice

Amphetamine is good, and it is free. Choose it when:

- You want rules. No built-in tool starts a session "while an external display is connected" or while you are on one Wi-Fi network.
- You want to click, not type.
- You keep a Mac awake for many different reasons: a download today, a presentation tomorrow.
- You do not want to pay.

For these needs we would not send you to any other tool, and not to ours.

## Alternatives by need

| Your need | Tool | Cost |
| --- | --- | --- |
| The screen should stay on | System Settings > **Lock Screen** | Built in |
| Awake for one command or a set time | `caffeinate` | Built in |
| One click, nothing else | KeepingYouAwake or Caffeine | Free |
| Rules and closed-display mode | Amphetamine | Free |
| Awake only while coding agents work | Agent Caffeine | Free |

### Built-in settings

To keep the screen on, open System Settings > **Lock Screen** and set the two **Turn display off** timers to Never. To keep a laptop awake on power while the screen is off, open System Settings > **Battery** > **Options** and turn on **Prevent automatic sleeping on power adapter when the display is off**. Our guide on [how to stop a Mac from sleeping](/blog/stop-mac-from-sleeping) has each step.

### caffeinate

`caffeinate` is a command that every Mac has. It needs no install:

```sh
caffeinate -i -t 3600
```

That keeps the Mac awake for one hour. Put a command after it, as in `caffeinate -i make`, and it keeps the Mac awake until that command ends. See [every caffeinate option with examples](/blog/caffeinate-mac).

### KeepingYouAwake

[KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) is open source under the MIT license. Its README calls it "a small wrapper around Apple's `caffeinate` command line utility" for macOS 10.13 and newer. Install it from its releases page or with `brew install --cask keepingyouawake`. The newest release, 1.6.8, is from September 12, 2025.

It does not keep a closed MacBook awake, and the README says so: it "will only prevent sleep on desktop Macs and portable Macs with an open lid." If you need the lid closed, use Amphetamine or one of the built-in ways in the lid guide linked above.

### Caffeine

Caffeine is the app with the coffee cup in the menu bar. Click the cup and the Mac stays awake. Its current version is from April 2026. Our [guide to Caffeine for Mac](/blog/caffeine-mac) says where to get it.

### Agent Caffeine

[Agent Caffeine](/) is our app, and it is for one case. You run coding agents such as Claude Code or Codex, and you want the Mac awake while they work and asleep when they are done.

Amphetamine can keep the Mac awake "while a specific app is running". A terminal with an agent in it runs all day, also while the agent sits idle or waits for your answer. Agent Caffeine reads from Claude Code and Codex whether they work, wait for you or are idle, and it knows more than 40 agents. It keeps the Mac awake while one works, also with the lid closed, and stops at a battery level, 20% by default, and when the Mac gets too hot.

It is free and open source, and needs macOS 13 or later. If you do not run coding agents, Amphetamine is the better choice.

<!-- faq -->

## Sources

- [Amphetamine on the Mac App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12) (description, version history, compatibility and privacy label, read on October 8, 2026)
- [Amphetamine resources on GitHub](https://github.com/x74353/Amphetamine) (how to install Power Protect)
- [Amphetamine Enhancer on GitHub](https://github.com/x74353/Amphetamine-Enhancer) (README and commit history)
- [KeepingYouAwake on GitHub](https://github.com/newmarcel/KeepingYouAwake) (README and releases)
- `man caffeinate` (caffeinate(8), macOS)
- Apple Support: [Set sleep and wake settings for your Mac](https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/mac)
