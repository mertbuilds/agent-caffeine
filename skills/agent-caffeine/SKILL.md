---
name: agent-caffeine
description: Keep this Mac awake while long work runs, with the Agent Caffeine command line tool. Use before any command or job that can run longer than a few minutes with nobody at the keyboard (builds, test suites, renders, training runs, backups, large downloads, migrations, deploys, long scripts, background servers you must wait for), and when the user says "keep my Mac awake", "do not let it sleep", "I will close the lid" or "run this overnight".
---

# Agent Caffeine

Agent Caffeine is a macOS menu bar app. It keeps the Mac awake while work runs and lets the Mac sleep when the work is done. It finds most coding agents by itself. It cannot see a plain command, a script or a long job. For those, ask it with `agent-caffeine`.

## Find the tool

```bash
command -v agent-caffeine || ls /Applications/[Aa]gent\ [Cc]affeine.app/Contents/MacOS/agent-caffeine
```

The app is `Agent Caffeine.app`, or `agent caffeine.app` when it was installed before version 1.0.2. If `agent-caffeine` is not on the PATH, use the full path that `ls` printed, in quotes. If the app is not installed, tell the user and continue the work without a hold. Do not install anything yourself.

## Hold while one command runs (preferred)

Put the tool in front of the command. The Mac stays awake while the command runs. The hold ends when the command ends. The exit code is the exit code of the command, and a signal sent to the tool is passed on to the command.

```bash
agent-caffeine hold --reason "Release build" -- npm run build
agent-caffeine hold --reason "Model training" -- python train.py
```

Use this form whenever the work is one command. Nothing is left to clean up. The hold ends after 24 hours at the latest. The command runs on.

If Agent Caffeine is not running, the command runs all the same, and the tool says on stderr that the Mac can sleep. Tell the user.

## Hold for a time

Use this when the work is not one command: many steps, a job on another machine that you wait for, or a background process.

```bash
agent-caffeine hold --for 45m --reason "Database migration"
# ... do the work ...
agent-caffeine release
```

- Times: `90s`, `30m`, `2h`, or parts in a row such as `1h30m`. With no `--for` the hold lasts 1 hour. The limit is 12 hours, and a longer time is refused.
- Ask for the time the work needs, with a small margin. Do not ask for the limit by habit.
- `hold` prints an id. `release` with no id ends the hold when there is only one. With more than one hold it ends nothing and lists them: release yours with `agent-caffeine release <id>`.
- Do not use `release --all`. It also ends holds that are not yours.
- Always release when the work is done or has failed. Do not leave a hold for the timer to end.
- If the work needs more time, ask for a new hold before the first one ends.

## Check

```bash
agent-caffeine status
agent-caffeine status --json
```

`status` lists the holds and says if the Mac can sleep now.

## Rules

- A hold is a request. Agent Caffeine still lets the Mac sleep at a low battery, when the Mac gets too hot, and when the user paused it or switched it off. The tool then says so on stderr, and the hold counts when the stop ends. Read `status` if the answer matters. Do not try to work around a stop.
- With the lid closed on battery, the Mac stays awake only when the user has set up the helper of Agent Caffeine. Do not promise it.
- If `hold --for` says that Agent Caffeine is not running, it made no hold. Tell the user. Do not start the app yourself, and do not use `caffeinate` or `pmset` in its place unless the user asks.
- Give a short reason in plain words (for example "Test suite", "Video render"). The user sees it in the menu, cut to 80 characters. Do not put secrets, paths with private names or long text in it.
- Do not hold for short work. A command that ends in a few minutes while the user is at the keyboard needs no hold.
- Do not hold "just in case" at the start of a session. Hold when the long work starts.
- One hold for one piece of work. Do not stack holds for the same job.

## MCP

If the tools `hold_awake`, `release` and `status` of the `agent-caffeine` MCP server are available, they do the same as `hold --for`, `release` and `status`. `hold_awake` takes minutes, from 1 to 720. A hold made through MCP ends when the session ends. For one long command, the command line form `hold -- <command>` is still the better choice.

## License

This file is under the MIT license. Copyright (c) 2026 Mert Duzgun. You can copy it into any agent or skill folder.
