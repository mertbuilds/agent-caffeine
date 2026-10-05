# 03 - Codex desktop "remote" mode: what it does, how it handles sleep, how to detect it

Snapshot: 2026-10-05, the owner's Mac. ChatGPT.app 26.928.21956 (bundle id com.openai.codex, Electron on Chromium 154), bundled codex CLI 0.159.x, openai/codex main at 823ea830 (2026-10-05).
Method: read-only. No process was started, stopped or configured. No secrets were read.

Legend: [DOC] = OpenAI docs/changelog. [SRC] = openai/codex source (local clone at `$TMPDIR/agent-caffeine-research/repos/openai_codex`). [BIN] = strings in the shipped app on this Mac. [MAC] = observed on this Mac. [3P] = third-party page only. [INFERRED] / [UNCONFIRMED] = not proven.

---

## 1. Codex remote feature set

### 1.1 Timeline (from the official changelog RSS, developers.openai.com/codex/changelog/rss.xml) [DOC]

| Date | Entry | What it added |
|---|---|---|
| 2026-02-02 | Introducing the Codex app | macOS app, multi-project, built-in worktrees, automations, skills |
| 2026-03-03 | Codex app | Handoff of a thread between Local and Worktree; worktree cleanup setting |
| 2026-03-12 | Codex app | Automations run "locally or on a worktree" |
| 2026-04-01 | Codex app | "early heartbeat automation affordances in threads", images for remote connections |
| 2026-04-16 | Codex can now help with more of your work | Computer Use (macOS), thread automations ("wake up the same thread on a schedule"), SSH remote connections in alpha, menu bar support |
| 2026-05-08 | Codex app | In-app trust review flow for hooks |
| 2026-05-14 | Work with Codex from anywhere | Codex from the ChatGPT mobile app connected to a Mac host. "Codex runs from the connected host, so the same projects, files, credentials, plugins, skills, and configuration are available from your phone." Hooks reach general availability |
| 2026-05-18 | ChatGPT for iOS | Open completed tasks from iOS notifications |
| 2026-05-21 | Appshots, goal mode, and more | Locked computer use: "Codex can use desktop apps after your Mac locks, including remotely via Codex Mobile", with "short-lived authorization, covered displays, relock on local input, and manual-unlock fallback" |
| 2026-05-29 | Computer use and mobile access on Windows | Remote control supports Windows hosts |
| 2026-06-18 | Record & Replay and remote task handoff | Thread handoff between local and remote hosts |
| 2026-06-25 | Codex Remote reaches general availability | "authenticated one-to-one QR pairing between each iOS or Android device and each host" |
| 2026-07-09 | Codex joins the ChatGPT desktop app | Codex ships inside ChatGPT.app (this is why the bundle id is com.openai.codex) |
| 2026-08-25 | Trigger scheduled tasks from Gmail, Slack, GitHub events | Event-triggered scheduled tasks (web and mobile) |
| 2026-09-08 | ChatGPT for iOS | Worktree setup continues in background with a Live Activity |
| 2026-09-22 | Codex CLI 0.156.0 | "Update the local background server through /daemon, or bypass it with --no-daemon"; worktree support on by default |
| 2026-09-25 | Codex CLI 0.157.0 | /import in remote sessions and "local background-server sessions" |
| 2026-09-28 | Codex CLI 0.158.0 | Bearer-token auth for direct exec-server WebSocket connections |

Not found in the changelog: the entry that introduced "Keep this Mac awake" or "Prevent sleep while running". [UNCONFIRMED date]

### 1.2 Remote connections (learn.chatgpt.com/docs/remote, /docs/remote-connections) [DOC]

- Setup: desktop app > Settings > Connections > "Control this Mac or PC" > Set up > scan QR code with the phone > same ChatGPT account.
- From the phone: start or continue chats in host projects, steer active work, approve commands, review diffs, test results, terminal output, screenshots, get notifications when a task completes or needs attention.
- Host requirement: "If that computer sleeps, loses network access, or closes the app, remote access stops until it's available again."
- Laptop: "On a Mac laptop, remote access can stay available with the lid open and power connected." "With the lid closed, connect an external display as well." "Choosing Sleep still stops remote access."
- Advice: "Use a dedicated always-on Mac or Windows PC when you want ChatGPT to stay reachable for longer-running work."
- Setting text: "Keep this Mac awake - Prevent sleep when computer is plugged in and remote access is enabled".
- After pairing, the setup dialog offers 4 toggles [BIN]: "Keep this Mac awake", "Enable computer use", "Use your Mac apps while locked", "Set up Chrome extension".
- SSH hosts: the app starts the remote Codex app server over SSH with the remote login shell. `codex` must be on the remote PATH.
- Page sections also cover "Local computer access with Work Cloud" and "Hand off a chat between hosts".

### 1.3 The machinery behind it [SRC]

- `codex app-server`: JSON-RPC server that owns threads and turns. Transports: `stdio://`, `unix://PATH`, `ws://IP:PORT`. All Codex clients (desktop, TUI, mobile through relay) talk to it.
- `codex app-server daemon ...` (crate `app-server-daemon`, marked experimental): `start | restart | update | enable-remote-control | disable-remote-control | stop | version | bootstrap --remote-control`. Each prints one JSON object. Pidfile-backed detached process plus a detached updater loop (checks after 5 minutes, then hourly). Settings file `CODEX_HOME/app-server-daemon/settings.json` with `remoteControlEnabled`, `shutdownGraceSeconds` (default 60, max 300), `updater.*`. README: "intended for Codex instances launched over SSH, including fresh developer machines that should expose app-server with `remote_control` enabled".
- Control socket: `CODEX_HOME/app-server-control/app-server-control.sock` (constants in `app-server-transport/src/transport/mod.rs`). Recovery file `loaded-threads.json` lets the daemon reload threads after restart.
- Remote control protocol methods: `remoteControl/enable`, `/disable`, `/pairing/start`, `/pairing/status`, `/client/list`, `/client/revoke`, `/status/read`, notification `remoteControl/status/changed`. Status enum: `disabled | connecting | connected | errored`. Relay endpoint in source: `wss://chatgpt.com/backend-api/wham/remote/control/server`.
- `codex exec-server` (crate `exec-server`): "a small JSON-RPC server for spawning and controlling subprocesses". Modes: `ws://IP:PORT`, `--remote URL --environment-id ID`, `forward`. Remote mode "registers the local exec-server with the environment registry, then reconnects to the service-provided rendezvous websocket as the environment", over a Noise relay. This is how a cloud-side harness runs commands on this Mac.
- Scheduled tasks [DOC, /docs/automations]: "Keep the computer on and the app running when a scheduled task needs local files." Runs local or in a worktree. Runs unattended with `approval_policy = "never"`. Results go to the "Scheduled" inbox. Web tasks run in OpenAI cloud and need no computer.

---

## 2. How Codex itself prevents sleep

There are three separate mechanisms. All are opt-in. All default to off.

### 2.1 CLI/TUI: `prevent_idle_sleep` feature [SRC][BIN]

- Crate `codex-rs/utils/sleep-inhibitor`. Doc comment: "Cross-platform helper for preventing idle sleep while a turn is running. macOS: Uses native IOKit power assertions instead of spawning `caffeinate`. Linux: Spawns `systemd-inhibit` or `gnome-session-inhibit`. Windows: `PowerCreateRequest` + `PowerSetRequest` with `PowerRequestSystemRequired`."
- macOS constants (`macos.rs` lines 23, 26): assertion type `PreventUserIdleSystemSleep`, reason string `"Codex is running an active turn"`. Created with `IOPMAssertionCreateWithName`, released on drop.
- Feature spec (`features/src/lib.rs` ~1910): key `prevent_idle_sleep`, stage Experimental, name "Prevent sleep while running", description "Keep your computer awake while Codex is running a thread.", `default_enabled: false`. User turns it on in `/experimental` or `[features] prevent_idle_sleep = true`.
- Only one caller: `tui/src/chatwidget/turn_lifecycle.rs`. `start()` acquires, `finish()` releases, `restore_running()` re-syncs on resume. So the assertion is held exactly from turn start to turn end, including time spent waiting for an approval (the turn is still running). The app-server does not use the crate.
- Shipped binary confirms it: it imports `_IOPMAssertionCreateWithName` and `_IOPMAssertionRelease`, links IOKit, and holds the strings `utils/sleep-inhibitor/src/macos.rs`, `PreventUserIdleSystemSleep`, `Codex is running an active turn`. No `caffeinate` string. [MAC]
- It does not block display sleep. It does not block lid-close sleep or a manual Sleep.

### 2.2 Desktop app: "Prevent sleep while running" (Settings > General) [BIN]

- Setting key `preventSleepWhileRunning`, default false, description "Whether the machine stays awake while Codex is running". UI text: "Keep your computer awake while {appName} is running a task". Hidden on Windows in this build.
- Implementation: Electron `powerSaveBlocker`. Renderer sends IPC `power-save-blocker-set` with `{shouldBlock, keepRemoteControlAwakeWhilePluggedIn, preventDisplaySleep}`. Main process `syncPowerSaveBlocker()`:
  - any window with `preventDisplaySleep` (set when a specific feature phase is `active`; which feature is not identified, likely voice or computer use [UNCONFIRMED]) -> `prevent-display-sleep`
  - else any window with `shouldBlock`, or (not on battery AND remote-control flag) -> `prevent-app-suspension`
  - else release.
- `shouldBlock` = setting on AND an in-progress conversation exists. So it is turn-scoped like the CLI one.
- Electron `prevent-app-suspension` maps to a `PreventUserIdleSystemSleep` assertion owned by the ChatGPT main process. The assertion name shown by pmset was not observed. [UNCONFIRMED name]

### 2.3 Desktop app: "Keep this Mac awake" (Settings > Connections) [DOC][BIN]

- Setting key `keepRemoteControlAwakeWhilePluggedIn`, default false, description "Whether remote control keeps this computer awake while plugged in". If unset it falls back to the stored value of `preventSleepWhileRunning`.
- Condition in code: `!powerMonitor.isOnBatteryPower()` AND remote control enabled for the local host (or a WSL host). It holds the blocker all the time while plugged in, not only during turns. On battery it releases.
- The app also listens to `suspend`, `resume`, `lock-screen`, `unlock-screen` (`isSystemSuspended`, `isScreenLocked`) for its own focus state.

### 2.4 Observed now [MAC]

- `pmset -g assertions`: no assertion from ChatGPT or codex. Holders were powerd, a `caffeinate` (300 s, not Codex), and `caffeinagent` (PreventUserIdleSystemSleep + PreventSystemSleep, "caffeinagent: agentWorking").
- Consistent with: both desktop settings unset (no key in `.codex-global-state.json`, defaults false), `prevent_idle_sleep` absent from `config.toml`, last turn finished 13:15, `remote_control_enrollments` table has 0 rows.

---

## 3. Local inspection

### 3.1 Processes (all 0.0 % CPU at sample time; app idle)

| Process | Parent | Role |
|---|---|---|
| `ChatGPT` 25328 | launchd | Electron main process. user-data-dir `~/Library/Application Support/Codex`. Holds `~/.codex/ipc/ipc.sock` (7 fds) |
| `codex -c features.code_mode_host=true app-server --analytics-default-enabled -c plugins...` 25445 | ChatGPT | The desktop app-server. stdio JSON-RPC to Electron. Owns all local threads. Holds open rollout files and `thread-writer-locks/*.lock` for loaded threads [MAC] |
| `codex app-server --listen stdio://` 27648 | node_repl 25854 | A second app-server started by the bundled Node REPL tool chain (config passes `CODEX_CLI_PATH` to the `node_repl` MCP server). Purpose: let plugin/REPL code talk to Codex [INFERRED] |
| `codex exec-server --remote https://codex-cloud-environments.chatgpt.com/api --environment-id ccarenv_...` 29747 | ChatGPT | Registers this Mac as an execution environment in the OpenAI environment registry (Noise relay). Lets a cloud-side Codex/Work Cloud harness run processes here [SRC]. Long-lived and idle; its presence does not mean work |
| `codex-code-mode-host` 45334 | app-server | Host process for "code mode" (crates `code-mode-host`, `code-mode-runtime`): runs model-written scripts that call tools [INFERRED from crate names] |
| `cua_node/bin/node ./server.mjs`, `cua-repl.mjs`, `node_repl` (5 sets) | app-server | Bundled Node runtime for the `node_repl` MCP server: browser use and computer use tooling. One set per loaded thread [INFERRED: 5 sets, 5 open rollouts] |
| `SkyComputerUseService` 4852 (`~/.codex/computer-use/Codex Computer Use.app`) | ChatGPT | Computer Use helper app (prefs domain `com.openai.sky.CUAService`). Does the screen reading, clicking, typing |
| `bare-modifier-monitor --key DoubleCommand` | ChatGPT | Global hotkey watcher |
| `Codex (Renderer)`, `Codex (Service)` gpu/network/storage/audio | ChatGPT | Chromium helpers |
| Sparkle `Autoupdate`, `Updater` | launchd | App updater |

No launchd agent for Codex exists (`~/Library/LaunchAgents` has none). The standalone daemon is not running: pids in `daemon.pid` (89090) and `daemon-updater.pid` (8333) are dead, `loaded-threads.json` is `[]`, no `app-server-control.sock` on disk.

### 3.2 `~/.codex` layout (names only)

- `sessions/YYYY/MM/DD/rollout-<ts>-<thread-uuid>.jsonl` (30 files). `session_index.jsonl`. `thread-writer-locks/<thread-uuid>.lock` (0 bytes, flock by the app-server).
- SQLite: `state_5.sqlite` (tables: threads, thread_spawn_edges, projects, remote_control_enrollments, thread_attachments, ...), `thread_history_1.sqlite` (44 MB), `logs_2.sqlite`, `queue_1.sqlite` (queued_items), `goals_1.sqlite`, `memories_1.sqlite`, `sqlite/codex-dev.db` (desktop: automations, automation_runs, inbox_items, local_thread_catalog*). The `threads` table has no status column; only `updated_at_ms`, `recency_at_ms`.
- `app-server-daemon/` (daemon.pid, daemon.lock, daemon-updater.pid, daemon-updater.sock, loaded-threads.json, stderr logs), `app-server-control/` (startup lock only), `packages/app-server-daemon/releases/0.159.{0,1,2}-aarch64-apple-darwin`, `packages/standalone/`.
- `ipc/ipc.sock` (desktop <-> TUI/IDE context IPC, `tui/src/ide_context/ipc.rs`), `computer-use/`, `plugins/`, `hooks.json`, `config.toml`, `.codex-global-state.json` (desktop settings), `shell_snapshots/`, `herdr-agent-state.sh` (a user hook script).
- `~/Library/Application Support/Codex` = Chromium profile. `~/Library/Application Support/com.openai.codex` = Sparkle appcast bootstrap only.
- `defaults read com.openai.codex` keys: Sparkle and Dock icon keys only. No sleep or remote keys. Info.plist: no sleep/remote keys; `NSAppleScriptEnabled = true`, `CFBundleAlternateNames = [Codex]`.
- `config.toml` keys: `notify`, `model`, `[features] hooks, js_repl`, `[mcp_servers.*]`, `[desktop]`, `[projects.*] trust_level`, `[hooks.state.*] trusted_hash`. No `prevent_idle_sleep`.

### 3.3 Rollout file format [SRC][MAC]

Each line: `{timestamp, ordinal, type, payload}`. Top-level `type` values seen: `session_meta`, `turn_context`, `world_state`, `response_item`, `event_msg`, `token_usage_record`, `compacted`. Source enum `RolloutItem` (`history/src/lib.rs`).

`event_msg` payload types that are persisted (`rollout/src/policy.rs`):
- `task_started` (enum `TurnStarted`; "v1 wire format uses `task_started`") - keys `turn_id, started_at, root_turn_id, ...`
- `task_complete` (`TurnComplete`) - keys `turn_id, completed_at, duration_ms, last_agent_message, ...`
- `turn_aborted` (`TurnAborted`, reasons `interrupted | replaced | review_ended | budget_limited`)
- `item_completed`, `token_count`, `thread_settings_applied`, `thread_goal_updated`, `thread_rolled_back`

Not persisted: `ExecApprovalRequest`, `ApplyPatchApprovalRequest`, `RequestPermissions`, `RequestUserInput`, `ElicitationRequest`, `ExecCommandBegin`, `ItemStarted`, all deltas. So:
- Working = last `task_started` has no later `task_complete` or `turn_aborted` for the same `turn_id`.
- Idle = last lifecycle event is `task_complete` or `turn_aborted`.
- Waiting for approval = not visible in the rollout. Looks the same as "working but silent".
- Crash caveat: a killed app-server leaves a dangling `task_started`. Cross-check that a live process holds the file open.
Observed: in the 6 newest files `task_started` and `task_complete` counts match exactly (1/1, 6/6, 3/3, 10/10, 1/1, 7/7).

### 3.4 App-server protocol signals [SRC]

- `thread/status/changed` with `ThreadStatus`: `notLoaded | idle | systemError | active { activeFlags: [waitingOnApproval | waitingOnUserInput] }`. This is the only first-party signal that separates working from waiting.
- `turn/started`, `turn/completed`, `item/started`, `item/completed`.
- Server requests: `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, `item/tool/requestUserInput`; `serverRequest/resolved` when answered.
- Queries: `thread/loaded/list`, `thread/list`, `thread/read`.
- Reachability: desktop app-server is stdio-only to Electron, so a third party cannot attach. The CLI background server (0.156+) listens on the unix control socket; a read-only client there is plausible but untested. [UNCONFIRMED]

### 3.5 Hooks and notify [DOC][SRC][MAC]

- Hook events (`HookEventName`): `PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, SessionStart, SessionEnd, UserPromptSubmit, SubagentStart, SubagentStop, Stop, Interrupt`.
- Common stdin fields: `session_id, transcript_path, cwd, hook_event_name, model, permission_mode`, plus `turn_id` for turn-scoped events. `PermissionRequest` adds `tool_name, tool_input`. `Stop` adds `stop_hook_active, last_assistant_message`. `SessionStart.source`: `startup | resume | clear | compact`.
- Locations: `~/.codex/hooks.json`, `[hooks]` in config.toml, `<repo>/.codex/hooks.json`, plugin hooks. "Before a non-managed hook can run, Codex requires you to review and trust the exact hook definition." Trust is stored as `[hooks.state."<path>:<event>:i:j"] trusted_hash` in config.toml.
- This Mac already has hooks for PermissionRequest (timeout 7200), PostToolUse, Pre/PostCompact, SessionStart, SessionEnd, Stop, SubagentStart/Stop, UserPromptSubmit, all trusted. Hooks run in the shared core, so the desktop app-server fires them too [INFERRED from trusted state + desktop-only usage; verify with one live turn].
- Legacy `notify` (`hooks/src/legacy_notify.rs`): one event only, `agent-turn-complete` with `thread_id, turn_id, cwd, client, input_messages, last_assistant_message`. No start event, no approval event.

---

## 4. Landscape

- Claude Code Remote Control [DOC code.claude.com/docs/en/remote-control]: `claude remote-control` (server mode, `--spawn same-dir|worktree|session`, `--capacity` default 32) or `/remote-control` in a session. Runs locally; phone/web is a window. "if your laptop sleeps or your network drops, Claude Code reconnects automatically when your machine comes back online." Server mode exits after roughly 10 minutes without network. Push notifications ("Push when actions required"). `CLAUDE_CLIENT_PRESENCE_FILE` suppresses pushes while the user is at the machine. No keep-awake setting; open request anthropics/claude-code#71875 asks for an AC-aware one.
- Cursor Cloud Agents [DOC cursor.com/help]: each agent runs on its own remote VM. "you can close your laptop and check the result later." Start from web, desktop, mobile, Slack, GitHub. Automations run on schedules or triggers (changelog 2026-03-05). Computer use in cloud agents (2026-02-24). No local keep-awake problem by design.
- Codex sits in between: local host with phone control (like Claude Code), plus first-party keep-awake, locked computer use, and a cloud-registered local executor.

---

## 5. Detection signals, ranked

1. Hooks. `UserPromptSubmit` = working. `PermissionRequest` = waiting for approval. `PostToolUse` after it = working again. `Stop` = idle. `Interrupt`/`SessionEnd` = idle. Same schema for CLI and desktop. Only source that gives all three states without a socket. Cost: user must trust hooks once; a crash sends no `Stop`.
2. Rollout tail. `task_started` vs `task_complete`/`turn_aborted`, plus file mtime as heartbeat. No setup. Cannot see approvals. Use `lsof`-style check (app-server holds the file) to drop stale files.
3. App-server `thread/status/changed` (`active` + `activeFlags`). Best data, but only reachable for the CLI background server socket, and that is untested.
4. Power assertion named "Codex is running an active turn" (CLI) or a ChatGPT-owned `PreventUserIdleSystemSleep` (desktop). Exact turn boundaries, zero cost, but only when the user turned the option on. Good as a "Codex already handles it" hint.
5. Process/CPU. `app-server`, `exec-server --remote`, `cua_node`, `SkyComputerUseService` all stay alive at 0 % while idle. Presence means "Codex is open", never "working". Use only as a gate for the other signals.

## 6. Ideas to borrow

1. AC-aware hold: keep awake for remote availability only when plugged in; drop on battery (Codex `keepRemoteControlAwakeWhilePluggedIn`).
2. Two separate switches: "awake while a task runs" (turn-scoped) and "awake while remote access is on" (availability-scoped). Different user intents.
3. Self-describing assertion reason ("Codex is running an active turn") so `pmset -g assertions` explains itself. Also detect foreign assertions and show "Codex already keeps the Mac awake".
4. Post-pairing checklist: after a remote tool is detected, offer keep-awake, lid-closed caveat ("needs power + external display"), and notification setup in one sheet.
5. Bounded grace on shutdown (`shutdownGraceSeconds` 60, max 300) and a recovery file (`loaded-threads.json`): let the Mac sleep only after a short grace, and resume state after wake.
6. Gap Codex leaves open: lid-closed sleep, manual Sleep, and scheduled tasks while asleep. Codex docs say "Keep the computer on and the app running". A wake-for-schedule or lid-closed mode is a real differentiator.

## Sources

- https://developers.openai.com/codex/changelog/rss.xml (redirects to learn.chatgpt.com)
- https://learn.chatgpt.com/docs/remote , https://learn.chatgpt.com/docs/remote-connections
- https://learn.chatgpt.com/docs/automations?surface=app , https://learn.chatgpt.com/docs/hooks
- openai/codex: `codex-rs/utils/sleep-inhibitor/src/{lib,macos}.rs`, `codex-rs/features/src/lib.rs`, `codex-rs/tui/src/chatwidget/turn_lifecycle.rs`, `codex-rs/app-server-daemon/README.md`, `codex-rs/exec-server/README.md`, `codex-rs/app-server-protocol/src/protocol/v2/{thread,remote_control}.rs`, `codex-rs/rollout/src/policy.rs`, `codex-rs/protocol/src/protocol.rs`, `codex-rs/hooks/src/legacy_notify.rs`, `codex-rs/app-server-transport/src/transport/mod.rs`
- https://code.claude.com/docs/en/remote-control , https://github.com/anthropics/claude-code/issues/71875
- https://cursor.com/help/ai-features/cloud-agents.md , https://cursor.com/changelog/03-05-26
- openai.com/index/work-with-codex-from-anywhere returned HTTP 403 to the fetcher; not read.
