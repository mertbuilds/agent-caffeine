---
title: "How to keep a Mac awake with the lid closed, monitor or not"
description: "Keep a MacBook awake with the lid closed: clamshell mode with a monitor, caffeinate on power, pmset disablesleep on battery, and how to turn each one off."
date: "2026-10-08"
updated: "2026-10-23"
faq:
  - q: "Can a MacBook stay awake with the lid closed without a monitor?"
    a: "Yes. On the power adapter, run `caffeinate -s` in Terminal before you close the lid. On battery, `sudo pmset -a disablesleep 1` is the only command that does it. Turn it off again with `sudo pmset -a disablesleep 0`."
  - q: "What is clamshell mode on a MacBook?"
    a: "Clamshell mode, which Apple calls closed-display mode, is when you use a MacBook with the lid closed on an external display. Apple asks that the Mac is connected to power and uses an external keyboard and mouse."
  - q: "Does pmset disablesleep stay on after a restart?"
    a: "Yes. macOS saves the setting to disk, so it stays on after a restart and until you run `sudo pmset -a disablesleep 0`. Check it with `pmset -g`: the line `SleepDisabled` shows 1 for on and 0 for off."
  - q: "Is it bad to keep a MacBook awake with the lid closed?"
    a: "On a desk with a monitor it is the way Apple supports. In a bag or on a bed it is a risk: the Mac has little air, so it can get hot, and on battery it drains until it is empty. Keep it awake only while you need it."
  - q: "Why does my Mac sleep with the lid closed while caffeinate runs?"
    a: "`caffeinate -i` and `-d` only stop idle sleep, and closing the lid is not idle sleep. `caffeinate -s` holds a closed lid, but its manual says it is valid only on AC power. On battery, no caffeinate flag keeps a closed MacBook awake."
---

A MacBook sleeps when you close the lid. To keep it awake, you have three ways: connect power, a monitor, a keyboard and a mouse (clamshell mode); run `caffeinate -s` while it is on the power adapter; or run `sudo pmset -a disablesleep 1`, which also works on battery and stays on until you turn it off.

Which one you need depends on two things: whether a monitor is connected, and whether the Mac is on power. The table below sorts the cases. After it, each method has its exact steps and its limits.

## What macOS does when you close the lid

Apple's Mac User Guide lists closing the display as one of the ways to put a Mac to sleep: "On a Mac laptop, close the display." This sleep is not the idle sleep that the timers in System Settings control. So a timer set to Never, or the option **Prevent automatic sleeping on power adapter when the display is off**, does not change what the lid does.

There are three cases:

- On power, with an external display, keyboard and mouse: the Mac stays awake and moves the picture to the external display. This is clamshell mode. Apple calls it closed-display mode.
- On power, without a display: the Mac sleeps, unless a program holds a system sleep assertion. `caffeinate -s` does that.
- On battery: the Mac sleeps. An assertion does not stop it. Only the system setting that turns sleep off does.

## Which method for which case

| Your case | Method | Works on battery | You must turn it off |
| --- | --- | --- | --- |
| Desk, with a monitor | Clamshell mode | No, Apple asks for power | No |
| On power, no monitor, one job | `caffeinate -s` | No | No, it ends with the job |
| On battery, no monitor | `sudo pmset -a disablesleep 1` | Yes | Yes |
| You want rules and a menu | Amphetamine | See its notes | You end the session |
| Awake only while coding agents work | Agent Caffeine | Yes, with its helper | No |

## With a monitor: clamshell mode

This is the way Apple supports. Apple's requirement, from its page on external displays: "If the display is connected to a Mac laptop computer with a closed lid, make sure that the Mac is connected to power and using an external keyboard and mouse."

1. Connect the MacBook to power.
2. Connect the external display.
3. Connect a keyboard and a mouse or trackpad, by cable or Bluetooth.
4. Close the lid.

The MacBook guide says the same from the other side: after you connect an external display, "you can use the display and accessories to use your MacBook Pro, even when the lid is closed."

If the display stays dark, press a key or click the mouse to wake the Mac. If it still sleeps, check the power first. Apple's requirement names power, so do not count on clamshell mode when the Mac runs on battery.

## On power, without a monitor: caffeinate -s

You want to close the lid and let a download, a backup or a build finish, and the Mac is on its power adapter. Run this in Terminal before you close the lid:

```sh
caffeinate -s
```

The `-s` flag creates an assertion "to prevent the system from sleeping". This is the assertion that keeps a closed MacBook awake on power. We rely on the same one in our own app. The manual adds the limit in the same paragraph: "This assertion is valid only when system is running on AC power."

To tie it to one job, put the command after it. caffeinate then ends when the job ends, and the Mac sleeps:

```sh
caffeinate -s ./backup.sh
```

Or give it a time in seconds. This is two hours:

```sh
caffeinate -s -t 7200
```

Press Ctrl+C to stop it early. If you pull the power cable while the lid is closed, the assertion no longer counts and the Mac sleeps. Our [guide to the caffeinate command](/blog/caffeinate-mac) explains every flag.

## On battery: pmset disablesleep

On battery, one command keeps a closed MacBook awake:

```sh
sudo pmset -a disablesleep 1
```

It asks for your password. `-a` applies the setting to all power sources. The `pmset` manual lists `-b` for battery and `-c` for the charger if you want only one of them.

Check the state at any time:

```sh
pmset -g
```

The first lines show `SleepDisabled 1` while it is on.

Know three things before you use it:

- It turns off all sleep, not only the sleep at the lid. The Mac also does not sleep when it is idle.
- It stays on. macOS saves the setting to disk, in `/Library/Preferences/com.apple.PowerManagement.plist`. It stays on after you close Terminal and after a restart, until you set it back.
- It is not in the manual. `man pmset` does not list `disablesleep`, so Apple does not document it and could change it.

Turn sleep back on when you are done:

```sh
sudo pmset -a disablesleep 0
```

Then run `pmset -g` again and make sure that `SleepDisabled` shows 0.

## Why caffeinate is not enough on battery

Many guides tell you to run `caffeinate` and close the lid. That fails, for two reasons:

- `caffeinate` with no flag, `-i` and `-d` stop idle sleep. Closing the lid is a different sleep.
- `-s` stops system sleep, but only on AC power.

So no caffeinate flag keeps a closed MacBook awake on battery. If your Mac slept in your bag while `caffeinate -i` ran, this is the reason.

## Apps that keep a closed Mac awake

Some menu bar apps do the same work with a click.

Amphetamine is free on the Mac App Store. Its description lists "Keep your MacBook awake while its display/lid is closed" and a session option for "System sleep when built-in display is closed". On Apple silicon laptops its developer offers a separate script named Power Protect for this mode. Our [guide to Amphetamine and its closed-display mode](/blog/amphetamine-mac) has the details.

KeepingYouAwake does not do this, and says so. From its README: "KeepingYouAwake will only prevent sleep on desktop Macs and portable Macs with an open lid."

Agent Caffeine is our app. It is for one case: you run coding agents and want the Mac awake only while they work. More on that below.

## Heat and battery

A closed MacBook that stays awake still makes heat and still uses its battery, and in a bag or under a blanket it has little air to cool down. Apple's guidance is to "use your Mac laptop on a stable work surface that allows for good ventilation" and not "in your bed, on a pillow, or under bedding", so keep an awake Mac on a table, and turn `disablesleep` off before you put the Mac in a bag.

## Test that it works

Do not trust a method until you have seen it work on your Mac. This writes the time to a file once per minute:

```sh
while true; do date >> ~/awake.log; sleep 60; done
```

Start it, set up your method, close the lid for ten minutes, then open the lid and read the file:

```sh
cat ~/awake.log
```

A line for every minute means that the Mac stayed awake. A gap of several minutes means that it slept. Press Ctrl+C to stop the loop and delete the file.

## When Agent Caffeine fits

`disablesleep` works, but you are the one who has to turn it on and remember to turn it off. We built [Agent Caffeine](/) for the case where the reason to stay awake is a coding agent, such as Claude Code or Codex, that works for an hour while you carry the Mac.

- It turns the sleep setting on only while an agent works, and turns it off again when the agents are done. Then the Mac sleeps as usual.
- On the power adapter a closed lid works from the start. On battery it needs a small helper that you allow once in System Settings.
- It stops at a battery level, 20% by default, and when the Mac gets too hot. Then it lets the Mac sleep and tells you why in a notification.

It has a 7-day free trial, then costs {{price}} once, and needs macOS 13 or later. If you do not run coding agents, the free methods above are the right ones. Our [guide on how to stop a Mac from sleeping](/blog/stop-mac-from-sleeping) covers the settings for an open lid.

<!-- faq -->

## Sources

- Apple Support: [Put your Mac to sleep or wake it](https://support.apple.com/guide/mac-help/put-your-mac-to-sleep-or-wake-it-mh10330/mac)
- Apple Support: [If your external display is dark or low resolution](https://support.apple.com/en-us/102501) (closed-display mode requirements)
- Apple Support: [Connect an external display to MacBook Pro](https://support.apple.com/guide/macbook-pro/connect-an-external-display-apd8cdd74f57/mac)
- Apple Support: [Keep your Mac laptop within acceptable operating temperatures](https://support.apple.com/en-us/102336)
- `man caffeinate` (caffeinate(8), macOS)
- `man pmset` (pmset(1), macOS)
- [Amphetamine on the Mac App Store](https://apps.apple.com/us/app/amphetamine/id937984704?mt=12)
- [KeepingYouAwake on GitHub](https://github.com/newmarcel/KeepingYouAwake)
