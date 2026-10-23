---
title: "Keep your Mac awake while a command runs"
description: "Keep a Mac awake until a build, a render or a backup ends: caffeinate -i in front of the command, its limit with the lid closed, and agent-caffeine hold."
date: "2026-10-09"
updated: "2026-10-23"
faq:
  - q: "How do I keep my Mac awake until a command finishes?"
    a: "Put `caffeinate -i` in front of it, for example `caffeinate -i npm run build`. The Mac does not idle sleep while the command runs, and normal sleep comes back when the command ends."
  - q: "Does caffeinate keep a MacBook awake with the lid closed?"
    a: "Only on the power adapter, and only with `caffeinate -s`. Its manual says that this assertion is valid only on AC power. On battery, no caffeinate flag keeps a closed MacBook awake."
  - q: "Does the exit code of my command change?"
    a: "No. `agent-caffeine hold -- <command>` ends with the exit code of the command, and in our test on macOS `caffeinate -i <command>` did the same. A script that checks the result works as before."
  - q: "Can an AI coding agent keep the Mac awake for its own long command?"
    a: "Yes, with Agent Caffeine. With its skill, an agent puts `agent-caffeine hold --` in front of a long command by itself. It can also call the tool `hold_awake` of the MCP server."
  - q: "What happens to the hold when the battery gets low?"
    a: "`caffeinate` does not look at the battery. Agent Caffeine lets the Mac sleep at 20% battery by default and when the Mac gets too hot, also while a hold is active."
---

To keep a Mac awake until a command ends, put `caffeinate -i` in front of it: `caffeinate -i npm run build`. The Mac does not idle sleep while the command runs, and it can sleep again when the command ends. This is built into macOS and it is free.

It has one limit that matters on a MacBook: it does not hold a closed lid on battery. This guide shows the built-in way first, then the same thing with `agent-caffeine hold`, the command line tool of our app Agent Caffeine, and then how an AI coding agent can ask for it by itself.

## The built-in way: caffeinate in front of the command

```sh
caffeinate -i npm run build
```

`caffeinate` starts the command and holds a power assertion while it runs. An assertion is a request to macOS not to sleep. The manual says that the assertions "will persist for the duration of the utility's execution". When the command ends, caffeinate ends too.

It works with any command:

```sh
caffeinate -i ./backup.sh
caffeinate -i python train.py
caffeinate -i rsync -a ~/Photos /Volumes/Backup
```

The `-i` flag prevents idle sleep. That is the sleep that comes when nobody touches the Mac for a while. The display can still turn off, and the job runs on. Add `-d` if the display must stay on too.

If the job already runs, tie caffeinate to its process ID in another tab:

```sh
caffeinate -i -w 4242
```

Our [guide to the caffeinate command](/blog/caffeinate-mac) explains every flag.

## The limit: a closed lid

Closing the lid is not idle sleep, so `-i` does not stop it. A MacBook sleeps when you close it, also while `caffeinate -i` runs, and the job stops until you open it again.

`caffeinate -s` prevents system sleep and holds a closed lid, but the manual adds: "This assertion is valid only when system is running on AC power." So:

| Your case | `caffeinate -i <command>` | `caffeinate -s <command>` |
| --- | --- | --- |
| Lid open | Works | Works on power |
| Lid closed, on power | The Mac sleeps | Works |
| Lid closed, on battery | The Mac sleeps | The Mac sleeps |

On battery with the lid closed, the only built-in way is `sudo pmset -a disablesleep 1`, which you must turn off yourself. Our [guide to the closed lid](/blog/keep-mac-awake-lid-closed) covers it, with its risks.

caffeinate also does not look at the battery level or at heat. A job that hangs keeps the Mac awake until the battery is empty.

## With Agent Caffeine: agent-caffeine hold

[Agent Caffeine](/) is our menu bar app. It keeps a Mac awake while AI coding agents work and lets it sleep after. It finds agents by itself, but it cannot see a plain script, a render, a model training run, a backup or a large download. It has a command line tool for those.

Put it in front of the command:

```sh
agent-caffeine hold -- npm run build
agent-caffeine hold --reason "Model training" -- python train.py
```

- The Mac stays awake while the command runs. The hold ends when the command ends.
- The exit code is the exit code of the command.
- The hold shows as a line in the menu of the app, with "Stop". The reason is its title.
- A hold for a command lasts 24 hours at most. The command itself runs on after that.

What it adds to caffeinate:

- **The closed lid.** On the power adapter a closed lid works from the start. On battery it works when you have allowed the small helper of the app once in System Settings.
- **Safety stops.** At a low battery, 20% by default, and when the Mac gets too hot, Agent Caffeine lets the Mac sleep, also while a hold is active. A pause and the switch of the app do the same.

If Agent Caffeine does not run, the command runs all the same, and the tool says that the Mac can sleep.

### Hold for a time

Some work is not one command: many steps, or a job on another machine that you wait for. Then ask for a time, and release it when the work is done:

```sh
agent-caffeine hold --for 45m --reason "Database migration"
# ... do the work ...
agent-caffeine release
```

Times are written as `90s`, `30m` or `2h`. With no `--for` the hold lasts 1 hour, and the limit is 12 hours. `agent-caffeine status` lists the holds and says whether the Mac can sleep now.

### Set it up

The tool is inside the app. In Settings, the button "Set up for agents" links it as `~/.local/bin/agent-caffeine`, so the command works in every terminal. Settings also shows the lines to link it by hand.

## Let a coding agent ask for it

An agent such as Claude Code or Codex often starts a long command itself: a test suite, a release build, a migration. Agent Caffeine sees most agents work, but two more ways make this certain.

**The skill.** A skill is a short text that tells an agent when and how to use a tool. "Set up for agents" in Settings adds the skill to the agents on your Mac: Claude Code, Codex, opencode, Cursor, Gemini CLI, Pi, Droid, Grok Build, Amp, goose and OpenClaw. With it, an agent puts `agent-caffeine hold --` in front of a long command by itself.

**The MCP server.** `agent-caffeine mcp` is an MCP server on stdio with three tools: `hold_awake`, `release` and `status`. `hold_awake` takes a number of minutes, from 1 to 720, and a reason. A hold that an agent made through MCP ends when the session of the agent ends, so nothing is left over when the agent quits.

For one long command, the form `agent-caffeine hold -- <command>` is the better choice: the hold ends exactly when the command does.

## Which one to use

- One command, lid open or on power: `caffeinate -i <command>`, or `caffeinate -s <command>` for a closed lid on power. It is free and already on your Mac.
- A closed lid on battery, or a job you leave alone for hours: `agent-caffeine hold -- <command>`, because it stops at a low battery and for heat.
- A coding agent that runs long commands: the skill, so the agent asks by itself.

Agent Caffeine has a 7-day free trial, then costs {{price}} once, and needs macOS 13 or later. The command line tool, the skill and the MCP server are in version 1.0.1 and later. If caffeinate covers your case, use caffeinate.

<!-- faq -->

## Sources

- `man caffeinate` (caffeinate(8), macOS)
- `man pmset` (pmset(1), macOS)
- [Model Context Protocol](https://modelcontextprotocol.io/) (what an MCP server is)
- The command line reference and the agent skill of Agent Caffeine
