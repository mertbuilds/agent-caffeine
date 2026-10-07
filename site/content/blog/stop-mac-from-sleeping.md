---
title: "How to stop a Mac from sleeping, also with the lid closed"
description: "Keep the screen on, keep the Mac awake with the display off, use caffeinate for one task, or keep a MacBook running with the lid closed. Exact steps."
date: "2026-10-05"
updated: "2026-10-05"
faq:
  - q: "How do I keep a MacBook Air awake?"
    a: "To keep the screen on, open System Settings > Lock Screen and set \"Turn display off on battery when inactive\" and \"Turn display off on power adapter when inactive\" to Never. To keep it awake for one task, run `caffeinate -i` in Terminal. With the lid closed, use closed-display mode with power, an external display, keyboard and mouse."
  - q: "How do I prevent my MacBook from sleeping when the lid is closed and an external monitor is connected?"
    a: "Connect the MacBook to power and use an external keyboard and mouse. Apple requires both for closed-display mode. Then close the lid and keep working on the external display."
  - q: "How do I keep a MacBook on while closed?"
    a: "With an external display, use closed-display mode. Without one, on power, `caffeinate -s` keeps it awake. On battery, the undocumented `sudo pmset -a disablesleep 1` does it; undo it with `sudo pmset -a disablesleep 0`, and never put an awake laptop in a bag."
  - q: "Does keeping a Mac awake hurt the battery?"
    a: "It uses more power, so the battery drains faster than when the Mac sleeps. Apple notes that preventing sleep may increase power consumption. Keep the Mac awake only while you need it, and on power when you can."
---

To stop a Mac from sleeping, set the display timers in System Settings > Lock Screen to Never, or run `caffeinate` in Terminal for one task. To keep a MacBook running with the lid closed, connect power, an external display, keyboard and mouse (closed-display mode), because the normal settings do not cover a closed lid.

Pick the section for what you want. The System Settings paths below are for current macOS (Sequoia 15 and later). Where macOS 13 Ventura or 14 Sonoma differ, we say so.

## 1. Keep the screen on

The screen turns off after a set time with no input. To change that:

1. Choose Apple menu > System Settings.
2. Click **Lock Screen** in the sidebar. You may need to scroll down.
3. Set **Turn display off on battery when inactive** to the time you want, or Never.
4. Set **Turn display off on power adapter when inactive** the same way.

This path is the same on macOS 13 and later.

This is also the fix for a movie: if your player does not keep the screen on, set the power adapter timer to Never while you watch, or run `caffeinate -d` in Terminal (more on that below).

## 2. Keep the Mac awake while the screen sleeps

Often you want the screen to go dark, but downloads, backups or builds to keep going. There is a setting for that.

**On a Mac laptop (macOS 14 Sonoma and later):**

1. Choose Apple menu > System Settings.
2. Click **Battery** in the sidebar.
3. Click **Options**.
4. Turn on **Prevent automatic sleeping on power adapter when the display is off**.

As the name says, this works only on the power adapter. On battery, the Mac still sleeps when the display turns off.

**On a desktop Mac:** go to System Settings > **Energy** and turn on **Prevent automatic sleeping when the display is off**. On macOS 13 and 14 the pane is called **Energy Saver**.

**On a laptop with macOS 13 Ventura**, Apple's guide places this option in the advanced Displays settings instead of Battery > Options.

## 3. For one task only: caffeinate

If you want the Mac awake only while one thing runs, you do not need to change any settings. Open Terminal and put `caffeinate` in front of the command:

```sh
caffeinate -i ./backup.sh
```

The Mac stays awake until the command ends. Or run it on its own for a fixed time, in seconds:

```sh
caffeinate -i -t 7200
```

That is two hours. Add `-d` to keep the screen on too. Press Ctrl+C to stop it early. Our full [guide to the caffeinate command on Mac](/blog/caffeinate-mac) covers every flag and the cases where it seems not to work.

## 4. With the lid closed

None of the settings above, and not `caffeinate -i`, stop a MacBook from sleeping when you close the lid. You have two options.

### Closed-display mode (clamshell mode)

This is the way Apple supports. Apple's requirement: "If the display is connected to a Mac laptop computer with a closed lid, make sure that the Mac is connected to power and using an external keyboard and mouse."

1. Connect the MacBook to power.
2. Connect an external display.
3. Connect an external keyboard and mouse or trackpad.
4. Close the lid. The Mac keeps running on the external display.

### Without a display

If you want the Mac to keep working with the lid closed and no display (for example, to finish a long job while you carry it to another room), there are two ways.

**On power:** `caffeinate -s` creates a `PreventSystemSleep` assertion. The `caffeinate` manual says it "is valid only when system is running on AC power". On power, this is the assertion that keeps a closed MacBook running; we rely on it in our own app.

**On battery:** run this in Terminal:

```sh
sudo pmset -a disablesleep 1
```

This turns sleep off completely, also with the lid closed on battery. It is widely used, but `disablesleep` is not in the `pmset` manual, so it is undocumented and could change. You can check its state with `pmset -g`, which shows `SleepDisabled` as 1 or 0.

A closed laptop that cannot sleep keeps using power. In a bag it has little air, so it can get hot, and the battery drains. Do not leave it on. When you are done, turn sleep back on:

```sh
sudo pmset -a disablesleep 0
```

## 5. Apps that keep a Mac awake

If you would rather click than type, these menu bar apps do the job. Each is good at something different.

**Amphetamine.** An app on the Mac App Store. You start sessions that last until you stop them, for a set time, or until a set time. Triggers start sessions on their own, for example while a certain app runs or while an external display is connected. It is the most complete option if you want rules.

**KeepingYouAwake.** A small menu bar app. Its README calls it "a small wrapper around Apple's `caffeinate` command line utility". Click the icon to keep the Mac awake for a set time or until you click again. Install it from its GitHub releases or with `brew install --cask keepingyouawake`.

**Caffeine.** A coffee cup in the menu bar. Click the cup and the Mac will not sleep, dim the screen, or start the screen saver. Click it again to stop. It does one thing and stays out of the way.

**agent caffeine.** Our app, for people who run AI coding agents like Claude Code, Codex or opencode. It detects more than 40 agents, and reads from Claude Code and Codex whether they work, wait for you or are idle. It keeps the Mac awake in one of three modes: always, while an agent is open, or while an agent is working. In the last mode the Mac can sleep again when every agent is idle, or has waited 5 minutes for your answer. A closed lid on the power adapter works from the start; on battery it needs a small helper that you allow once. It has a 7-day free trial, then costs {{price}} once, and needs macOS 13 or later. See [agent caffeine](/) for details. If you do not run agents, one of the apps above is the better fit.

## 6. Mac mini and other desktop Macs

A Mac mini, iMac, Mac Studio or Mac Pro has no battery, so only the desktop settings apply:

- System Settings > **Lock Screen** for the display timer.
- System Settings > **Energy** (called **Energy Saver** on macOS 13 and 14) for **Prevent automatic sleeping when the display is off**.

To prevent a Mac mini from sleeping for good, turn that option on. A desktop has no lid, so `caffeinate -i` covers the rest for one-off jobs.

## 7. Check what keeps your Mac awake, or why it will not sleep

If your Mac will not sleep, or sleeps when you do not expect it, Terminal can tell you why.

**See who holds the Mac awake right now:**

```sh
pmset -g assertions
```

Look under "Listed by owning process". Each line names a process and what it prevents, for example `PreventUserIdleSystemSleep` (idle sleep) or `PreventUserIdleDisplaySleep` (display sleep). A browser playing video, an audio app, or a forgotten `caffeinate` often shows up here.

**See your settings and what overrides them:**

```sh
pmset -g
```

Next to `sleep`, it lists the processes that are preventing sleep.

**See the history of sleeps and wakes:**

```sh
pmset -g log
```

The manual describes it as "a history of sleeps, wakes, and other power management events". The output is long, so filter it. For example, this shows the last 20 lines about assertions:

```sh
pmset -g log | grep -i assertion | tail -20
```

Apple also lists common causes: the "Prevent automatic sleeping on power adapter when the display is off" option is on, "Wake for network access" is on, other people use shared files or printers on your Mac, or a connected device does not work as it should.

<!-- faq -->

## Sources

- Apple Support: [Set sleep and wake settings for your Mac](https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/mac) (also the [macOS 15](https://support.apple.com/guide/mac-help/mchle41a6ccd/15.0/mac/15.0), [macOS 14](https://support.apple.com/guide/mac-help/mchle41a6ccd/14.0/mac/14.0) and [macOS 13](https://support.apple.com/guide/mac-help/mchle41a6ccd/13.0/mac/13.0) versions)
- Apple Support: [If your external display is dark or low resolution](https://support.apple.com/en-us/102501) (closed-display mode requirements)
- Apple Support: [If your Mac sleeps or wakes unexpectedly](https://support.apple.com/guide/mac-help/if-your-mac-sleeps-or-wakes-unexpectedly-mchlp2995/mac)
- `man caffeinate` (caffeinate(8), macOS)
- `man pmset` (pmset(1), macOS)
- [Amphetamine on the Mac App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)
- [KeepingYouAwake on GitHub](https://github.com/newmarcel/KeepingYouAwake)
- [Caffeine](https://www.caffeine-app.net/en/)
