---
title: "The caffeinate command on Mac: every option, with examples"
description: "caffeinate is a built-in macOS command that stops your Mac from sleeping. Every flag, timeouts, the lid-closed limit, and how to use it with coding agents."
date: "2026-10-05"
updated: "2026-10-05"
faq:
  - q: "Does caffeinate work on a Mac?"
    a: "Yes. `caffeinate` is part of macOS and lives at `/usr/bin/caffeinate`. Open Terminal, type `caffeinate`, and your Mac will not idle sleep until you press Ctrl+C."
  - q: "Is there a caffeinate app for Mac?"
    a: "The command itself has no app, but several menu bar apps do the same job with a click. KeepingYouAwake is a small wrapper around `caffeinate`. Amphetamine and Caffeine are other options, and Agent Caffeine keeps the Mac awake while coding agents work, also with the lid closed."
  - q: "Why isn't the caffeinate command working on my Mac?"
    a: "The usual reasons: you closed the lid, the display went dark because you did not add `-d`, the timeout ran out, or you closed the Terminal window that ran it. Run `pmset -g assertions` to see if caffeinate still holds an assertion."
  - q: "Does caffeinate work with the lid closed?"
    a: "Not by default. With the lid closed a MacBook sleeps even while `caffeinate -i` runs. `caffeinate -s` on power, clamshell mode with an external display, or the undocumented `sudo pmset -a disablesleep 1` are the ways around it."
  - q: "How do I turn caffeinate off?"
    a: "Press Ctrl+C in the Terminal window where it runs. From another window, run `killall caffeinate`. With `-t` it stops by itself when the timeout ends."
---

`caffeinate` is a command built into macOS that stops your Mac from sleeping while it runs. Type `caffeinate` in Terminal and the Mac stays awake until you press Ctrl+C; add a command after it, like `caffeinate -i make`, and it stays awake until that command finishes.

You do not need to install anything. The tool lives at `/usr/bin/caffeinate` on every Mac, so there is no Homebrew package to add. This guide covers every option in its manual, the limits you will hit, and how we use it with AI coding agents.

## What caffeinate does

The manual describes it in one line: "prevent the system from sleeping on behalf of a utility". It does this with power assertions. An assertion is a request to macOS that says "do not sleep right now". When caffeinate exits, the assertion goes away and normal sleep settings apply again.

caffeinate works in two ways:

- **On its own.** It holds the assertion until it exits: when you press Ctrl+C, when a timeout ends, or when a process you told it to watch ends.
- **In front of a command.** It runs the command and holds the assertion for as long as that command runs.

## The default with no flags

```sh
caffeinate
```

With no flags, caffeinate prevents idle sleep. That is the same as `caffeinate -i`. Your display can still turn off on its normal timer. The Mac itself keeps running, so downloads, builds and scripts continue. Press Ctrl+C to stop it.

## Every flag, with an example

### -d: keep the display on

Prevents the display from sleeping.

```sh
caffeinate -d
```

Use it for a presentation, a dashboard, or a long video in a player that does not keep the screen on itself.

### -i: prevent idle sleep

Prevents the system from idle sleeping. This is what you want for most long jobs.

```sh
caffeinate -i
```

### -m: prevent disk idle sleep

Prevents the disk from idle sleeping.

```sh
caffeinate -m
```

### -s: prevent system sleep on power

Prevents the system from sleeping. The manual adds an important limit: "This assertion is valid only when system is running on AC power." On battery, `-s` does nothing.

```sh
caffeinate -s
```

### -u: declare that the user is active

Tells macOS that a user is active. If the display is off, this turns it on and stops it from going into idle sleep. Without `-t`, this assertion lasts only 5 seconds, so pair it with a timeout:

```sh
caffeinate -u -t 600
```

### -t: stop after a number of seconds

Sets how long the assertion lasts, in seconds. When the time is up, caffeinate exits.

```sh
caffeinate -i -t 3600
```

Some values you can copy:

- 30 minutes: `-t 1800`
- 1 hour: `-t 3600`
- 2 hours: `-t 7200`
- 8 hours: `-t 28800`

The timeout is ignored when you give caffeinate a command to run.

### -w: wait for a process to exit

Holds the assertion until the process with a given process ID (PID) exits. This is useful when a long job is already running and you forgot to start it with caffeinate.

```sh
caffeinate -i -w 12345
```

To find the PID, use `pgrep` with the process name, for example `pgrep -x rsync`. You can put the two together:

```sh
caffeinate -i -w "$(pgrep -n -x rsync)"
```

`-w` is ignored when you give caffeinate a command to run.

### Combine flags

Flags stack. This keeps both the display and the system awake for two hours:

```sh
caffeinate -d -i -t 7200
```

## Wrap a command

The example in the manual is the most useful form:

```sh
caffeinate -i make
```

caffeinate starts `make` and holds the assertion while `make` runs. When `make` ends, caffeinate ends too. This works with any command:

```sh
caffeinate -i ./backup.sh
caffeinate -i npm run build
caffeinate -i rsync -a ~/Photos /Volumes/Backup
```

## How to stop caffeinate

- Press Ctrl+C in the Terminal window where it runs.
- From any other window, run `killall caffeinate`.
- With `-t`, wait for the timeout. With `-w` or a wrapped command, it stops when that process ends.

## See what keeps your Mac awake

Run this to list every assertion and the process that holds it:

```sh
pmset -g assertions
```

A running caffeinate shows up under "Listed by owning process" with a line like this:

```text
pid 302(caffeinate): [...] PreventUserIdleSystemSleep named: "caffeinate command-line tool"
```

`pmset -g` (with no option) also lists, next to the `sleep` setting, the processes that currently prevent sleep.

## The limits: what caffeinate cannot do

**Closing the lid still sleeps a MacBook.** `-i`, `-d`, `-m` and `-u` only stop idle sleep. They do not stop the sleep that happens when you close the lid. `-s` holds a `PreventSystemSleep` assertion, which on power is what keeps a closed MacBook running (we rely on it in our own app). On battery `-s` is not valid, so nothing caffeinate offers keeps a closed MacBook awake.

There are two ways around this:

1. **Clamshell mode.** Apple calls it closed-display mode. Connect the MacBook to power, an external display, and an external keyboard and mouse. Then you can close the lid and keep working. The steps are in our guide on [how to stop a Mac from sleeping, also with the lid closed](/blog/stop-mac-from-sleeping).
2. **`sudo pmset -a disablesleep 1`.** This stops the Mac from sleeping at all, also with the lid closed on battery. It is widely used but it is not in the `pmset` manual, so treat it as undocumented. A closed laptop that stays awake in a bag can get hot and drain the battery. Turn it off again when you are done:

```sh
sudo pmset -a disablesleep 0
```

`pmset -g` shows the current state as `SleepDisabled` (1 is on, 0 is off).

## Why caffeinate "does not work"

- **The lid is closed.** See the limits above.
- **The screen went dark.** Without `-d`, the display sleeps on its normal timer while the Mac stays awake. Add `-d` if you need the screen on.
- **`-s` on battery.** It is valid only on AC power.
- **The timeout ran out.** `-t` is in seconds, not minutes. `-t 60` is one minute.
- **You closed the Terminal window.** Closing a terminal window sends a hangup signal to the processes in it, and caffeinate exits on hangup. Keep the window open while you need it.
- **`-u` without `-t`.** It lasts only 5 seconds.

## caffeinate with Claude Code, Codex and other coding agents

Coding agents like Claude Code, Codex and opencode can work for a long time without input from you. If the Mac sleeps, the agent stops in the middle of its task. caffeinate fixes this in two ways.

**Wrap the agent:**

```sh
caffeinate -i claude
```

The same works for `caffeinate -i codex` or `caffeinate -i opencode`. The Mac stays awake for as long as the agent's session is open. When you quit the agent, the assertion goes away.

**Or run caffeinate in another tab:**

```sh
caffeinate -i
```

Open a second tab, run it, and leave it there. It keeps the Mac awake for every agent you start, until you press Ctrl+C. Add `-t 14400` if you want it to stop by itself after four hours. If an agent is already running, `caffeinate -i -w` with its PID ties the assertion to that one process.

Both work. Both fail in two ways:

1. **You forget to run it.** You start an agent, walk away, and come back to a sleeping Mac and a task half done.
2. **It does nothing for a closed lid on battery.** You close the MacBook to take it with you, and the agent stops.

There is also a cost the other way: a wrapped agent holds the Mac awake while it sits idle at its prompt, waiting for you.

That is why we built [Agent Caffeine](/), a menu bar app that does this automatically. It detects more than 40 coding agents, and reads from Claude Code and Codex whether they work, wait for you or are idle. It keeps the Mac awake in one of three modes: always, while an agent is open, or while an agent is working. A closed lid on the power adapter works from the start. On battery it needs a small helper that you allow once. It has a 7-day free trial, then costs {{price}} once, and needs macOS 13 or later. If caffeinate in a tab works for you, keep using it.

## caffeinate on Windows and Linux

caffeinate is a macOS tool, so it does not exist on Windows. The closest equivalent there is Awake in Microsoft PowerToys, which keeps Windows awake for a set time or until a process ends, or you can change the power and sleep settings in Windows itself.

On Linux with systemd, `systemd-inhibit` plays the same role: it runs a command with a sleep, idle and shutdown inhibitor lock, so `systemd-inhibit sleep 3600` blocks sleep for an hour.

<!-- faq -->

## Sources

- `man caffeinate` (caffeinate(8), macOS)
- `man pmset` (pmset(1), macOS)
- Apple Support: [If your external display is dark or low resolution](https://support.apple.com/en-us/102501) (closed-display mode requirements)
- Microsoft Learn: [PowerToys Awake](https://learn.microsoft.com/en-us/windows/powertoys/awake)
- `systemd-inhibit(1)` manual page ([man7.org](https://man7.org/linux/man-pages/man1/systemd-inhibit.1.html))
- Apple Support: [Set sleep and wake settings for your Mac](https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/mac)
