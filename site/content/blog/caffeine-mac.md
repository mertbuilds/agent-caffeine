---
title: "Caffeine for Mac: the app, the command and what to use today"
description: "Caffeine for Mac can mean the menu bar app with the coffee cup, the caffeinate command, or any keep-awake tool. Where to get each one, and which one fits you."
date: "2026-10-08"
updated: "2026-10-23"
faq:
  - q: "Is there still a Caffeine app for Mac?"
    a: "Yes. The Caffeine app with the coffee cup is maintained again. Version 1.6.4 is on caffeine-app.net, and was released on April 20, 2026. Version 1.6.4 needs macOS 14.6 or later. For an older macOS, the site offers an older version: choose your macOS there."
  - q: "Is Caffeine for Mac free?"
    a: "The download on caffeine-app.net has no price, and the app is open source under the MIT license."
  - q: "Is there a caffeine command on Mac?"
    a: "No. The command is named `caffeinate`, and it is at `/usr/bin/caffeinate` on every Mac. `caffeinate -d` keeps the display on, and `caffeinate -i` keeps the Mac awake while the display sleeps."
  - q: "What is the difference between Caffeine and caffeinate?"
    a: "Caffeine is a menu bar app that you download. `caffeinate` is a command that is part of macOS and runs in Terminal. Both stop the Mac from sleeping by itself."
  - q: "Does Caffeine keep a MacBook awake with the lid closed?"
    a: "Its site does not say so. It says that Caffeine prevents the Mac \"from automatically going to sleep, dimming the screen or starting screen savers\". For a closed lid, use clamshell mode, `caffeinate -s` on power, or `sudo pmset -a disablesleep 1`."
---

"Caffeine for Mac" means one of three things, so find your case first:

- You want the Caffeine app, the coffee cup in the menu bar. It still exists. Download version 1.6.4 from [caffeine-app.net](https://www.caffeine-app.net/en/). Version 1.6.4 needs macOS 14.6 or later. For an older macOS, the site offers an older version: choose your macOS there.
- You mean the command. It is named `caffeinate`, not caffeine, and it is on every Mac. Open Terminal and run `caffeinate -d` to keep the display on until you press Ctrl+C.
- You want any tool that keeps your Mac awake. For the screen, set the timers in System Settings > **Lock Screen** to Never. For other cases, the table near the end of this guide names the tool.

The rest of this guide has the details for each case, and a short part on `caffeinate` with Claude Code.

## The Caffeine app

Caffeine is a small app with one job. Its site describes it: "Caffeine is a tiny open source program that puts an icon in the right side of your menubar. Click it to prevent your Mac from automatically going to sleep, dimming the screen or starting screen savers."

### Where it comes from

Many people know Caffeine from years ago and are not sure if this is the same app. The site answers that: "Yes! Tomas Franzén of Lighthead Software originally developed Caffeine in 2006". Development then stopped for a long time. In 2018 Michael Jones of IntelliScape Computer Solutions asked to continue it, and the site says that Tomas "has graciously provided the source code under an open source license". The current line started later: "In 2022 we started modernizing the codebase and added support for macOS 11 and above."

### The current version

These are the facts we read on October 8, 2026:

| Fact | What the source says |
| --- | --- |
| Version | 1.6.4, 4.5 MB |
| Released | April 20, 2026 (GitHub release) |
| Needs | macOS 14.6 or later (the update feed of the app). The site says "at least macOS 11 (Big Sur)" |
| macOS versions the site lists | Monterey, Ventura, Sonoma, Sequoia, Tahoe |
| License | MIT, source on GitHub |
| Site | caffeine-app.net, copyright Dominic Rodemer |

For a Mac with macOS 10.x, the site points to the older version from IntelliScape.

Two things to know when you look for it:

- Homebrew has a cask named `caffeine`. On the day we checked, it installs version 1.1.4 from the IntelliScape repository, not version 1.6.4. The current version is also a cask: `domzilla-caffeine` installs version 1.6.4. Or use the download on caffeine-app.net.
- The Mac App Store has several apps with "Caffeine" in the name from other makers. They are different apps. We did not find this Caffeine there.

### How to use it

1. Download Caffeine and move it to the Applications folder. Open it.
2. Click the coffee cup in the menu bar. The site explains the icon: "a full cup means Caffeine will prevent your Mac from automatically going to sleep, dimming the screen or starting screen savers. An empty cup means your Mac will sleep normally."
3. For a time limit, right-click the cup, or hold Command and click it. The menu has the settings and a timeout.

In the settings you can start Caffeine when you start your Mac, make it active each time it starts, and set a default duration.

### What it does not do

Caffeine does one thing. It has no rules that start it for you, and its site does not mention a closed lid. Its makers say this themselves: "we believe that Caffeine's power lies in its simplicity and ease of use". If you want rules, see our [guide to Amphetamine for Mac](/blog/amphetamine-mac). If you want the lid closed, see [how to keep a Mac awake with the lid closed](/blog/keep-mac-awake-lid-closed).

## The caffeinate command

If you typed "caffeine" and meant the Terminal command, the name is `caffeinate`. There is no `caffeine` command on a Mac. You do not install anything: it is at `/usr/bin/caffeinate`.

| You want | Command |
| --- | --- |
| Mac awake, display may sleep | `caffeinate -i` |
| Display on | `caffeinate -d` |
| Mac and display awake | `caffeinate -d -i` |
| Awake for one hour | `caffeinate -i -t 3600` |
| Awake until a command ends | `caffeinate -i make` |
| Awake with the lid closed, on power | `caffeinate -s` |
| Stop it | Ctrl+C, or `killall caffeinate` |

`-t` takes seconds, so 3600 is one hour. With no flag at all, `caffeinate` prevents idle sleep, the same as `-i`.

Our [guide to the caffeinate command](/blog/caffeinate-mac) has every flag, the cases where it seems not to work, and how to see what keeps your Mac awake.

## caffeinate with Claude Code

Coding agents such as Claude Code can work for a long time without input from you. If the Mac sleeps, the agent stops in the middle of its task. So people put `caffeinate` in front of the agent:

```sh
caffeinate -i claude
```

caffeinate starts `claude` and holds its assertion for as long as that process runs. The manual says this about a command you give it: "those assertions will persist for the duration of the utility's execution". When you quit Claude Code, the Mac can sleep again. The same form works for other agents, for example `caffeinate -i codex`.

To keep the display on too, add `-d`:

```sh
caffeinate -d -i claude
```

This works, and it is free. It has three limits:

- It does not know what the agent does. The Mac stays awake while Claude Code works, and also while it waits for your answer or sits idle at its prompt, for as long as the session is open.
- It does not hold a closed lid on battery. `-i` stops idle sleep only. `-s` holds a closed lid, but the manual says it "is valid only when system is running on AC power".
- You must remember it each time. A session that you started without it is not covered. You can add it later with `caffeinate -i -w` and the process ID of the agent.

[Agent Caffeine](/) is our app for this part. It sits in the menu bar and finds the agents by itself, so there is nothing to type. It reads from Claude Code and Codex whether they work, wait for you or are idle. It keeps the Mac awake while an agent works, for 5 minutes when one waits for your answer, and then lets the Mac sleep. It also holds a closed lid: on the power adapter from the start, and on battery with a small helper that you allow once. On battery it stops at 20% by default.

It has a 7-day free trial, then costs {{price}} once, and needs macOS 13 or later. If `caffeinate -i claude` does the job for you, keep it.

## What to use today

If you only want the Mac to stay awake, choose by your need:

| Your need | Use | Cost |
| --- | --- | --- |
| Screen on during a talk or a film | System Settings > **Lock Screen**, or `caffeinate -d` | Built in |
| Awake while one command runs | `caffeinate -i` and the command | Built in |
| One click in the menu bar | Caffeine or KeepingYouAwake | Free |
| Rules, for example "while a display is connected" | Amphetamine | Free |
| Lid closed at a desk with a monitor | Clamshell mode | Built in |
| Lid closed on battery | `sudo pmset -a disablesleep 1` | Built in |
| Awake only while coding agents work | Agent Caffeine | {{price}} once |

For most people a built-in way is enough. Our guide on [how to stop a Mac from sleeping](/blog/stop-mac-from-sleeping) has the steps for each setting. The `pmset` command in the table stays on until you turn it off, so read the lid guide linked above before you use it.

Caffeine is the right one when you want a single switch in the menu bar and nothing to learn. [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) is close to it: its README says that it is "inspired by Caffeine" and that it is "a small wrapper around Apple's `caffeinate` command line utility".

<!-- faq -->

## Sources

- [Caffeine](https://www.caffeine-app.net/en/) (description, history, version and system requirements, read on October 8, 2026)
- [Caffeine on GitHub](https://github.com/domzilla/Caffeine) (release 1.6.4 and its date, license)
- [Caffeine update feed](https://dr-caffeine-mac.s3.amazonaws.com/appcast.xml) (the macOS version that each release needs)
- [Homebrew cask caffeine](https://formulae.brew.sh/cask/caffeine) (version and source of the cask)
- [Homebrew cask domzilla-caffeine](https://formulae.brew.sh/cask/domzilla-caffeine) (version of the cask)
- `man caffeinate` (caffeinate(8), macOS)
- [KeepingYouAwake on GitHub](https://github.com/newmarcel/KeepingYouAwake)
- [Amphetamine on the Mac App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)
