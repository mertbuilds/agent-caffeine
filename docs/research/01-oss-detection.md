# 01 - How open source projects detect AI coding agent state

Research date: 2026-10-05. Read-only research for the Agent Caffeine detection redesign.

Method: shallow clones of each repo at HEAD (in `./repos/`), source read with grep and sed. Official docs fetched with WebFetch. One local check on this Mac (Claude Code 2.1.289).

Evidence labels used below:

- **[SRC]** = I read the logic in the source file at the commit shown.
- **[LOCAL]** = I checked it on this Mac.
- **[DOC]** = official documentation page, fetched today.
- **[README]** = only the README or an issue says so. Not confirmed in code.
- **[UNCONFIRMED]** = could not confirm.

---

## 0. Headline findings

1. **Claude Code publishes its own live state on disk.** `~/.claude/sessions/<pid>.json` has `status` and `statusUpdatedAt`. No hook is needed. [LOCAL] on 2.1.289: 12 files, one per live `claude` process, values seen `busy` and `idle`. Other tools report `waiting` and `shell` too [README]. This file is not in the official `.claude` directory docs (grep of the docs page found no match), so it is undocumented and can change.
2. **Every serious multi-agent tool uses layers, not one signal.** Order is: agent-reported state (hooks, plugin, SSE, state file) with a freshness window, then terminal screen rules, then activity heuristics.
3. **Hooks alone are not enough.** Proven gaps: Esc interrupt fires no Claude hook, Stop can arrive late, a crash sends nothing, background work continues after Stop.
4. **Only one project does what Agent Caffeine does today (ps + CPU): `ovedaydin/agent-mode`.** It adds network bytes from `nettop` and switches to hooks when hooks are present.
5. **Screen scraping needs to own the pty or tmux.** A menu bar app does not have that. Those rule sets are still useful as a catalogue of states.

---

## 1. Sleep-prevention tools (direct peers)

### 1.1 ovedaydin/agent-mode (macOS menu bar, Swift) - closest to Agent Caffeine
- URL: https://github.com/ovedaydin/agent-mode - commit 57d25ae (2026-10-05)
- Logic: `Sources/Agents.swift` (`ProcessTable`, `AgentTracker`), `Sources/CLI.swift` (hook CLI), `Sources/AppDelegate.swift` (10 s tick, 120 s sleep delay). [SRC]
- Signals:
  - `ps -Axo pid=,ppid=,%cpu=,comm=` every 10 s. Process names: `claude, codex, aider, gemini, cursor-agent, opencode, amp, goose`. Sums CPU over the process subtree. Threshold `cpuThreshold = 5.0`.
  - **Network**: `nettop -P -L 1 -J bytes_in -x`, per-pid delta. `networkThreshold = 2048` bytes per check ("idle sessions get a few hundred").
  - `activityGrace = 180` s after last activity.
  - Optional hooks: `agent-mode hook [busy|idle|waiting]`. Reads Claude hook JSON on stdin, or the Codex `notify` payload as last argv (`agent-turn-complete`). Sends to the app with `DistributedNotificationCenter`. Finds the agent pid by walking up the process tree from the hook process.
  - Once a session sends one hook, `hooked = true` and **hooks are the source of truth**. CPU and network are then only a keep-alive: `hookBusy && (heartbeatFresh || recentlyActive)`, `heartbeatTimeout = 1800` s.
  - After an idle or waiting hook it sets `ignoreActivityUntil = now + 30 s`. Comment: "CPU use decays slowly in `ps`, so don't let it re-mark the session as working right away."
- States: working / waiting (hooks only) / idle / gone (pid missing from ps).
- Latency: 10 s poll without hooks. Near instant with hooks.
- Install: none for passive mode. Claude hooks and Codex `notify` line are optional.
- Failure modes: without hooks it cannot tell "waiting for permission" from "idle". CPU from an unrelated child (dev server started by the agent) counts as work. `nettop` is one more process spawn per tick.

### 1.2 jmslau/claude-caffeine (and skater4 fork, same commit)
- URL: https://github.com/jmslau/claude-caffeine - commit c124886 (2026-08-22)
- Logic: `Sources/ClaudeCaffeine/ClaudeHookMonitor.swift`, `HookInstaller.swift`, `CursorHookInstaller.swift`. [SRC]
- Signal: hooks write one file per session in `~/.claude/caffeine_sessions/<session_id>` with `{timestamp, pid}` (pid = hook's ppid). "Active" hooks: `UserPromptSubmit, PreToolUse, PostToolUse`. "Idle" hooks delete the file: `Stop, StopFailure, SubagentStop, Elicitation, Notification`.
- App polls the directory. A session counts when the file exists **and** `kill(pid, 0) == 0` **and** age < 300 s (`hookStaleThreshold`).
- Cursor: `~/.cursor/hooks.json` with `beforeSubmitPrompt, preToolUse, postToolUse, beforeShellExecution, afterAgentThought, subagentStart` (active) and `stop, sessionEnd` (idle).
- States: working / not working. No separate "waiting".
- Install: writes into `~/.claude/settings.json` and `~/.cursor/hooks.json`.
- Failure modes: a single tool call longer than 300 s with no hook traffic goes stale (long build, long test). `SubagentStop` deletes the file while the parent turn still runs. Any `Notification` (also `auth_success`) marks idle.

### 1.3 jpbarbosa/awakebar
- URL: https://github.com/jpbarbosa/awakebar - commit 1ab3eeb (2026-09-22)
- Logic: `keep-awake.sh`, `notify-attention.sh`, `claude-hook-contract.sh`, `Sources/AwakeBar/AwakeMonitor.swift`. [SRC]
- Signal: Claude hooks only. `UserPromptSubmit` starts `caffeinate -i -m -s -t 14400` (4 h cap). `Stop` kills it. `SessionEnd` always releases. **One caffeinate per session** in `/tmp/claude-keep-awake.d/<session>.pid`. Comment: a shared hold breaks with two sessions, "whichever one reaches Stop first releases the Mac".
- Also reads `~/.claude/sessions/<pid>.json` for `sessionId` and `bridgeSessionId` (Remote Control), and sweeps holds whose session pid is dead ("Session gone without a SessionEnd").
- `Notification` hook = "blocked on you (needs tool permission, or the prompt idled >=60s)". Attention alerts wait a grace period and are dropped if the per-cwd activity marker moves.
- States: turn running / remote-held / attention needed / released.
- Failure modes: Esc interrupt leaves the hold until the 4 h cap or pid death. Claude only.

### 1.4 majiayu000/caff
- URL: https://github.com/majiayu000/caff - commit 045cc42 (2026-10-02)
- Logic: `Sources/CaffCore/AgentHookManager.swift`, `AgentActivityCooldown.swift`. [SRC]
- Signal: "touch" model. Hooks on Claude (`UserPromptSubmit, SessionStart, PreToolUse, PostToolUse, Stop`) and Codex (`UserPromptSubmit, PreToolUse, PostToolUse, Stop`) run `caff agent-touch --source X --cooldown-seconds N`. Every event, also `Stop`, restarts a cooldown (default 1800 s).
- States: recently active / not. Nothing else.
- Failure modes: stays awake 30 minutes after every finished turn. A tool call longer than the cooldown lets the Mac sleep.

### 1.5 bmoeskau/caffeinate-claude
- URL: https://github.com/bmoeskau/caffeinate-claude - commit e485f96 (2026-03-27)
- Logic: `hooks/per-command/*.sh`, `hooks/session/*.sh`, `examples/combined.json`. [SRC]
- Signal: plain hook scripts. Per-command mode `UserPromptSubmit` -> caffeinate, `Stop` -> kill. Session mode `SessionStart` / `SessionEnd`.
- Failure modes: single shared hold, no interrupt handling, no pid check.

---

## 2. Passive readers of agent-written state (no install)

### 2.1 rorhcdream/tmux-agent-status - the key find
- URL: https://github.com/rorhcdream/tmux-agent-status - commit afb2a2d (2026-09-29)
- Logic: `scripts/poller.sh` (866 lines). [SRC]
- **Claude**: reads `~/.claude*/sessions/<pid>.json`, `jq '.status, (.statusUpdatedAt // .updatedAt)'`. Maps pane -> `pane_pid` -> child `claude` pid. Mapping: `busy`, `shell` -> working. `waiting` -> waiting. `idle` -> done. No process -> cleared.
- README reason [README]: hook trackers break because "when you interrupt a turn with Esc, Claude fires no hook, so the window stays stuck on the working icon". The file is updated "on every transition, including interrupts".
- **Codex**: no per-pid file. Finds the open `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` with one `lsof -a -c codex -Fn` call for all processes. Reads a bounded tail. Last turn-boundary event decides: `task_started` -> busy, `task_complete` -> idle, `turn_aborted` -> cleared. Caches the file set per pid because handles close between turns.
- Newer Codex clients delegate file handles to a shared app-server. Then it matches by cwd, and leaves status blank if two sessions share a cwd.
- States: working / waiting (Claude only) / done / gone.
- Latency: poll interval (configurable, sub-second allowed).
- Failure modes: undocumented file. Codex has no "waiting for approval" in the rollout (see 5.2). cwd matching is ambiguous.

### 2.2 pbauermeister/claude-busy-monitor [README only]
- URL: https://github.com/pbauermeister/claude-busy-monitor
- Reads `~/.claude/sessions/<pid>.json` `status`. Raw values `busy / shell / idle / waiting` map to `busy / asking / idle`. "Claude Code v2.1.119 introduced the required `status` field; older sessions are ignored." Linux only (`/proc`).

### 2.3 Field notes on `~/.claude/sessions/<pid>.json`
- [LOCAL] keys on 2.1.289: `pid, sessionId, cwd, startedAt, procStart, version, kind (interactive|bg), entrypoint, status, updatedAt, statusUpdatedAt, name, messagingSocketPath, peerProtocol, jobId`, sometimes `agent`, `spare`, `parkedJobId`. Also a `<pid>.<hash>.key` file beside it.
- [LOCAL] idle sessions keep an old `statusUpdatedAt` (seen 174,570 s old while the pid was alive).
- [README] tuiboard issue #22: "Claude Code doesn't rewrite that file while a turn runs, so any turn longer than 5 minutes flips from live-busy to stale". **Do not put a staleness timeout on `busy`.** Use `kill(pid, 0)` and `procStart` for liveness. https://github.com/NazzarenoGiannelli/tuiboard/issues/22
- [README] kelpie issue #12: status is `shell` when the foreground turn ended and background work still runs. https://github.com/snaka/kelpie/issues/12
- [LOCAL] 2026-10-11, correction: `shell` means that a background command of the session is alive, not that it works. It is not `busy`, and it must not hold the Mac by itself. See section 9.
- [UNCONFIRMED] exact meaning of `waiting` (permission, question, or both). I did not see it locally.
- awakebar also uses this directory (`sessionId`, `bridgeSessionId`). [SRC]

---

## 3. Session managers and multiplexers

### 3.1 asheshgoplani/agent-deck (Go, tmux) - most complete engine
- URL: https://github.com/asheshgoplani/agent-deck - commit 34cf369 (2026-10-04)
- Files [SRC, headers and constants read; not every line]: `internal/session/claude_hooks.go`, `hook_lag.go`, `opencode_sse.go`, `codex_live_rollout.go`, `codex_live_thread.go`, `pi_hooks.go` + `assets/pi/agent-deck.ts`, `cursor_hooks.go`, `gemini_hooks.go`, `internal/tmux/title_detection.go`, `patterns.go`, `codex_live_status.go`, `background_work.go`, `completed_turn.go`.
- Layers:
  1. **Claude hooks** write a per-instance status file. Events: `SessionStart, UserPromptSubmit, Stop, PermissionRequest, Notification (matcher permission_prompt|elicitation_dialog), SessionEnd, PreCompact`. A "running" hook is trusted for `hookFastPathWindow = 2 min`.
  2. **Pane title**: Claude sets the title by OSC. Braille U+2800-28FF = working. Done markers `✳✻✽✶✢` = finished, then check the prompt.
  3. **Pane content** rules per agent (spinner line, "esc to interrupt", menus).
  4. **Codex**: hooks trusted for only 20 s (running) and 5 s (waiting). Then a regex for the live status line `... (12s • esc to interrupt)` placed right above the `› ` composer. Live thread found by the open `$CODEX_HOME/thread-writer-locks/<thread-id>.lock`.
  5. **opencode**: SSE `GET /event` on the TUI's HTTP server (only when launched with `--port`). `session.status {type: busy|retry|idle}`, `session.idle`. Snapshot at `GET /session/status`. Freshness 30 s, then fall back to tmux.
  6. **pi**: extension dropped in `~/.pi/agent/extensions/`. Events `session_start, turn_start, turn_end, session_shutdown`.
  7. **Gemini**: `SessionStart, BeforeAgent, AfterAgent, SessionEnd`. **Cursor**: `sessionStart, sessionEnd, beforeSubmitPrompt, preToolUse, postToolUse, stop`.
- Two documented defects that matter to us:
  - **Hook lag** (`hook_lag.go`): hook file said "running" (UserPromptSubmit) while the pane showed a finished turn; Stop came minutes late. Cause unknown. Tie-break: two "completed turn at idle prompt" samples 3 s apart override the hook.
  - **Background work** (`background_work.go`, issue #2473): "a running workflow means a running session". Claude ends the foreground turn and Stop fires while workflows, background agents, `run_in_background` shells and Monitors still run. They match `Waiting for N background agents to finish`, the workflow progress row, and the footer counter `· 2 shells, 1 monitor ·`.
- States: running (with substate) / waiting / idle / error / gone.

### 3.2 ogulcancelik/herdr (Rust, own terminal runtime)
- URL: https://github.com/ogulcancelik/herdr - commit 040d345 (2026-10-05)
- Files [SRC]: `src/detect/manifests/*.toml` (22 agents: amp, antigravity, claude, cline, codex, cursor, devin, droid, gemini, github-copilot, grok, hermes, kilo, kimi, kiro, letta, maki, muse, opencode, pi, qodercli, qwen), `src/pane/agent_detection.rs`.
- Signal: **declarative, versioned TOML rule manifests** over the terminal screen and OSC title. Each rule has `state`, `priority`, `region` (`osc_title`, `bottom_non_empty_lines(12)`, `prompt_box_body`, `after_last_horizontal_rule`), regex, and `not` guards.
- Claude manifest: `osc_title_working` rule = title starts with Braille U+2800-28FF **or half-circles U+25D0-25D3**. Comment: "Braille covers <= 2.1.227; half-circles are the 2.1.228 busy spinner." So the title glyph changed in one release.
- Rules for blocked forms ("esc to cancel" + "enter to confirm"), MCP elicitation, dynamic workflow prompt, background agents, `/btw` overlay.
- Debounce: working -> idle needs 3 confirmations at 100 ms, cap 700 ms. Startup grace 3 s.
- States: working / blocked / idle / unknown.
- Install: none. Needs to own the pty.
- Failure modes: every agent UI change needs a manifest update (they ship manifest updates, see `manifest_update.rs`). rrnewton/agent-utils issue #179 reports working Claude panes read as idle [README].

### 3.3 njbrake/agent-of-empires (Rust, tmux)
- URL: https://github.com/njbrake/agent-of-empires - commit 6a42d96 (2026-10-04)
- Files [SRC]: `src/hooks/status_file.rs`, `src/hooks/codex.rs`, `src/hooks/json_settings.rs`, `src/tmux/status_detection.rs`, `src/tmux/detect/manifests/*.toml` (antigravity, claude, codex, copilot, cursor, droid, gemini, hermes, omp, opencode, pi, qwen, vibe).
- Signal: hooks write one word (`running|waiting|idle|error`) to `/tmp/aoe-hooks-<euid>/<instance_id>/status`. The manifest engine takes screen text, OSC title **and** the hook observation with its **age** (file mtime). Comment: freshness tells "a genuinely fresh running (a turn that just started, spinner not yet rendered) from a stale one that a missed idle hook left standing".
- Claude hooks: `SessionStart, UserPromptSubmit (running), PreToolUse (running), PostToolUse, Stop (idle), Notification, ElicitationResult (running)`. Codex hooks: `SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, Stop`.
- User-configurable status rules outrank built-ins.

### 3.4 manaflow-ai/cmux (macOS terminal app, Swift)
- URL: https://github.com/manaflow-ai/cmux - commit b5282b3b (2026-10-05)
- Files [SRC]: `CLI/CMUXCLI+AgentHookCatalog.swift`, `CLI/CMUXCLI+AgentHookDefinitions.swift`, `CLI/CMUXCLI+ClaudeHookSettings.swift`, `Resources/bin/cmux-claude-wrapper`, `Resources/opencode-plugin.js`, `CLI/CMUXCLI+AmpExtensionSourcePart3.swift`.
- **Best catalogue of per-agent hook formats.** Config path, format and events for: codex (`~/.codex/hooks.json`: SessionStart, UserPromptSubmit, Stop + feed PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop), grok (`~/.grok/hooks/*.json`: SessionStart, UserPromptSubmit, Stop, Notification, SessionEnd), opencode (plugin `~/.config/opencode/plugins/*.js`), pi (`~/.pi/agent/extensions/*.ts`), amp (plugin `~/.config/amp/plugins/*.ts`), cursor (`~/.cursor/hooks.json`: beforeSubmitPrompt, stop, afterAgentResponse, beforeShellExecution, afterShellExecution, postToolUseFailure), gemini (`~/.gemini/settings.json`: SessionStart, BeforeAgent, AfterAgent, SessionEnd), kiro, antigravity (`~/.gemini/config/hooks.json`: SessionStart, PreInvocation, Stop, turn-completion, Notification, SessionEnd; binary `agy`), rovodev, hermes, copilot (`~/.copilot/config.json`), codebuddy, factory droid (`~/.factory/settings.json`: SessionStart, Stop, Notification, SessionEnd; binary `droid`), qoder.
- **Claude without touching user config**: a PATH wrapper injects `--session-id` and `--settings <generated json>` with hooks `SessionStart, Stop, StopFailure, SessionEnd, Notification, UserPromptSubmit, SubagentStop, PreToolUse, PermissionRequest`.
- opencode plugin listens to `session.created, session.status, session.idle, permission.asked, message.updated`. Comment: "OpenCode has emitted both session.idle and session.status events over time, and the session identifier moved between top-level and nested properties."
- Amp plugin: `amp.on("session.start" | "agent.start" | "tool.call" | "tool.result" | "agent.end")`. Newer Amp exposes an authoritative `thread.state`; older releases do not.
- States: running / needs input / idle / ended, per agent.

### 3.5 superset-sh/superset
- URL: https://github.com/superset-sh/superset - commit a6de0c8 (2026-10-05)
- Files [SRC]: `packages/agent-setup/templates/notify-hook.template.sh`, `codex-wrapper-exec.template.sh`, `opencode-plugin.template.js`, `pi-extension.template.ts`, `amp-plugin.template.ts`, `cursor-hook.template.sh`, `gemini-hook.template.sh`, `copilot-hook.template.sh`.
- Signal: one shared hook script for all agents, POSTs to a local host service. Normalises `hook_event_name` (Claude, Droid, Kimi), `hookEventName` (Grok) and Codex `type` (`agent-turn-complete|task_complete` -> Stop, `task_started` -> Start, `exec_approval_request|apply_patch_approval_request|request_user_input` -> PermissionRequest).
- Codex wrapper sets `CODEX_TUI_RECORD_SESSION=1` and tails the **process-scoped TUI session log** for start and permission events. Comment: "Avoid tailing global rollout files: concurrent Codex sessions share that directory."
- Hard-won gotchas written in the script:
  - "cursor-agent replays `~/.claude/settings.json`, so Claude's config fires inside a Cursor session." They drop it using `CURSOR_AGENT`/`CURSOR_CLI` env.
  - Claude's Bash tool running `codex exec` fires Codex's hooks under a Claude terminal.
  - Hooks with `agent_id` come from a subagent. "Subagent activity must not drive terminal-level agent status."

### 3.6 generalaction/emdash
- URL: https://github.com/generalaction/emdash - commit a39d9c8 (2026-10-01)
- Files [SRC]: `packages/core/src/runtimes/tui-agents/node/runtime/agent-state.ts`, `packages/plugins/src/agents/impl/*/hooks.ts`.
- Signal: per-agent hook plugins mapped to canonical `start | stop | error | notification | session`. Attention types: `permission_prompt, idle_prompt, elicitation_dialog`. Droid hooks: `UserPromptSubmit, Notification, Stop, SessionStart`.

### 3.7 kbwo/ccmanager
- URL: https://github.com/kbwo/ccmanager - commit ee0af83 (2026-09-27)
- Files [SRC]: `src/services/stateDetector/{claude,codex,gemini,cursor,opencode,github-copilot,cline,kimi}.ts`.
- Signal: regex over its own headless xterm buffer.
  - Claude: waiting = `/(do you want|would you like).+\n+[\s\S]*?(yes|❯)/`, `esc to cancel`, `\d+\.\s*deny\s*\(esc\)`. Busy = `esc to interrupt` / `ctrl+c to interrupt` above the prompt box, spinner label, token stats line. Else idle, **debounced 1500 ms**: "Claude Code sometimes appears idle in terminal output while still actively processing".
  - Codex: `allow command?`, `[y/n]`, `press enter to confirm or esc to cancel`; busy `/esc.*interrupt/`.
  - Gemini: `waiting for user confirmation`, `│ Allow execution`, `│ Apply this change`; busy `esc to cancel`.
  - Cursor: `(y) (enter)`, `keep (n)`, `skip (esc or n)`; busy `ctrl+c to stop`.
  - opencode: `△ Permission required`; busy `/esc.*interrupt/`.
- States: busy / waiting_input / idle. Also counts Claude background tasks from the footer.

### 3.8 smtg-ai/claude-squad
- URL: https://github.com/smtg-ai/claude-squad - commit ce1ffb4 (2026-08-20)
- File [SRC]: `session/tmux/tmux.go` `HasUpdated()`.
- Signal: `tmux capture-pane`, SHA-256 of the content. Changed = Running. Unchanged = Ready. Prompt = fixed strings: Claude `No, and tell Claude what to do differently`, Aider `(Y)es/(N)o/(D)on't ask again`, Gemini `Yes, allow once`.
- Failure modes: a long silent tool call reads as Ready. Cursor blink or clock changes read as Running. One string per agent breaks on any copy change.

### 3.9 coder/agentapi
- URL: https://github.com/coder/agentapi - commit 7c468d5 (2026-09-13)
- Files [SRC]: `lib/screentracker/pty_conversation.go`, `lib/httpapi/server.go`.
- Signal: agent runs in an in-memory terminal. Snapshots on an interval. Screen unchanged for `ScreenStabilityLength = 2 s` -> `stable`. Else `running`.
- States: running / stable only. Agent-agnostic. Cannot tell "waiting for permission" from "idle".

### 3.10 amantus-ai/vibetunnel
- URL: https://github.com/amantus-ai/vibetunnel - commit f78324f (2026-08-05)
- File [SRC]: `web/src/server/pty/activity-status.ts`.
- Signal: last pty output or input timestamp. Active if within `DEFAULT_ACTIVITY_IDLE_TIMEOUT_MS = 5000`. I found no Claude-specific status parser at HEAD.

### 3.11 farouqaldori/claude-island (notch app)
- URL: https://github.com/farouqaldori/claude-island - commit 10f1d24 (2026-04-20)
- Files [SRC]: `ClaudeIsland/Resources/claude-island-state.py`, `Services/Hooks/HookSocketServer.swift`, `Services/Session/JSONLInterruptWatcher.swift`.
- Signal: Python hook sends JSON to Unix socket `/tmp/claude-island.sock`. Mapping: `UserPromptSubmit` -> processing, `PreToolUse` -> running_tool, `PostToolUse`/`PostToolUseFailure`/`PermissionDenied` -> processing, `PermissionRequest` -> waiting_for_approval (hook blocks and waits for the app's answer), `Notification idle_prompt` -> waiting_for_input, `Stop`/`StopFailure` -> waiting_for_input, plus `SubagentStop, SessionStart, SessionEnd, PreCompact`.
- **Interrupt gap fix**: a `DispatchSource` watcher on the transcript JSONL looks for `[Request interrupted by user]`, `[Request interrupted by user for tool use]`, `"interrupted":true`. So they combine hooks with transcript tailing.

### 3.12 Octane0411/open-vibe-island and wxtsky/CodeIsland (open notch apps)
- URLs: https://github.com/Octane0411/open-vibe-island (b50f87a, 2026-09-15), https://github.com/wxtsky/CodeIsland (b444ae2, 2026-09-24)
- [SRC, file level only] open-vibe-island: hook installers for Claude, Codex, Cursor, Gemini, Grok; hook CLI -> Unix socket -> app. Plus `ActiveAgentProcessDiscovery.swift` (ps + lsof to find tool, tty, cwd, transcript path) on a ~2 s tick, and transcript discovery. Codex hook enum: `SessionStart, PreToolUse, PermissionRequest, PostToolUse, UserPromptSubmit, Stop`.
- CodeIsland: `HookServer.swift` + transcript tailer. Not read in depth.
- **Vibe Island** itself is closed source. [UNCONFIRMED] Its site says per-agent hook integrations over a socket.

### 3.13 Tools that own the agent process (state comes for free)
These start the agent themselves in a structured mode. They know state from the protocol and from process exit. This does not help an outside observer, but shows the protocols.
- **Dimillian/CodexMonitor** (dd61b9a, 2026-03-26) [SRC, grep]: spawns `codex app-server`. Uses `turn/started`, `turn/completed`, `thread/status/changed`, `item/started`, `item/completed`, `item/tool/requestUserInput`, `*/requestApproval`.
- **pingdotgg/t3code** (78122305, 2026-10-05) [SRC, file names only]: `CodexAdapterV2.ts` (Codex app-server) and `AcpAdapterV2.ts` (ACP).
- **BloopAI/vibe-kanban** (d5cbb53, 2026-09-19) [SRC, grep]: Claude with `--output-format=stream-json --input-format=stream-json`, Codex with `app-server`, opencode SDK.
- **winfunc/opcode** (d1ca30a) [SRC, grep]: Claude `stream-json`, emits `claude-complete` on process end.
- **stravu/crystal** (1e18e0b, 2026-02-26) [SRC, grep]: panel status `running / waiting / stopped / completed_unviewed` from its own process and exit code.
- **slopus/happy** (dafe9a5, 2026-10-03) [SRC]: `packages/happy-cli/scripts/claude_local_launcher.cjs` patches `global.fetch` inside the Claude process and writes `fetch-start` / `fetch-end` to fd 3. "Thinking" = a fetch is in flight. Also a SessionStart hook server for the session id.
- **ComposioHQ/agent-orchestrator** (7b7db96) [SRC, file names only]: per-agent hooks (devin, cline, droid, copilot), Codex app-server driver, Claude ACP driver.
- **omnara-ai/omnara** (3e9edc1, 2026-10-02): repo is now a Go harness. I found no terminal-state detector. [UNCONFIRMED]
- **Conductor**: closed source. [UNCONFIRMED]

### 3.14 tmux status plugins
- **accessd/tmux-agent-indicator** (553c3cc) [SRC]: `hooks/codex-hooks.json` = `UserPromptSubmit` running, `PermissionRequest` needs-input, `Stop` done. Same for Claude. opencode plugin: `session.status busy`, `permission.updated|permission.asked`, `session.idle`, `session.error`.
- **nipunravisara/tmux-agent-status** (efe7caf) [SRC, grep]: Claude hooks + `~/.codex/hooks.json` + Codex `notify =` (`agent-turn-complete`).
- **Abstrucked/tmux-agentic-plugin** (babe2c1) [SRC, grep]: hooks + `capture-pane` "esc to interrupt" + pane title + opencode plugin.
- **RatulMaharaj/tmux-agent-status** (bc7364f) [SRC, grep]: `pane_current_command` + `capture-pane` "esc to interrupt". No hooks.
- **CRThaze/tmux-handlr** (88230bb) [SRC, grep]: `detection/*.json` rule files for 22 agents, synced from an upstream by a CI job (`detection/UPSTREAM.json`, `sync-detection.yml`). The id list matches herdr's manifest list.

---

## 4. Not a detector
- **sirmalloc/ccstatusline** (35440e4): renders the Claude status line. The status line command is only run by Claude Code; see 5.1.
- **ccusage-style monitors**: parse transcripts for tokens and cost. No live state.

---

## 5. Official extension points

### 5.1 Claude Code
- **Hooks** [DOC] https://code.claude.com/docs/en/hooks - events today: SessionStart, Setup, UserPromptSubmit, UserPromptExpansion, PreToolUse, PermissionRequest, PermissionDenied, PostToolUse, PostToolUseFailure, PostToolBatch, Notification, MessageDisplay, SubagentStart, SubagentStop, TaskCreated, TaskCompleted, Stop, StopFailure, TeammateIdle, InstructionsLoaded, ConfigChange, CwdChanged, DirectoryAdded, FileChanged, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, PreModelSwitch, PostModelSwitch, Elicitation, ElicitationResult, SessionEnd.
  - Notification matchers: `permission_prompt, idle_prompt, auth_success, elicitation_dialog, elicitation_url_dialog, elicitation_complete, elicitation_response, agent_needs_input, agent_completed, quota_auto_resume_*`.
  - SessionEnd reasons: `clear, resume, logout, prompt_input_exit, other`. StopFailure types: `rate_limit, overloaded, authentication_failed, billing_error, server_error, max_output_tokens, ...`.
  - Common input: `session_id, prompt_id, transcript_path, cwd, permission_mode, hook_event_name`, and `agent_id` / `agent_type` only inside a subagent.
  - Hook types: `command`, **`http`** (POST to a URL, so a menu bar app can run a localhost listener with no helper binary), `mcp_tool`, `prompt`, `agent`. `async: true` exists.
  - Ways to install without editing the user's file: `--settings <json>` (cmux), or a plugin.
- **Status line** [DOC] https://code.claude.com/docs/en/statusline - event-driven, debounced 300 ms, optional `refreshInterval`. In-flight script is cancelled on a new update. No busy/idle field noted. **"With a custom status line configured, Claude Code stops showing most of the footer's keyboard hints, including `esc to interrupt`."** This breaks screen scrapers that match that string.
- **OpenTelemetry** [DOC] https://code.claude.com/docs/en/monitoring-usage - events `claude_code.user_prompt, assistant_response, tool_result, api_request, api_error, tool_decision, permission_mode_changed, ...`. Logs export every 5 s by default, metrics every 60 s. There is **no turn-end, idle or waiting event**. Needs env vars and a local OTLP receiver. Poor fit.
- **Terminal** [DOC] https://code.claude.com/docs/en/terminal-config - desktop notification by escape sequence only in Ghostty, Kitty and iTerm2 by default; `preferredNotifChannel: "terminal_bell"` for others. Fires "when Claude finishes a task or pauses for a permission prompt, and you appear to be away". Inside tmux needs `allow-passthrough on`. The title spinner is used by agent-deck, herdr and AoE [SRC]; the docs page did not describe it.
- **Session state file** `~/.claude/sessions/<pid>.json`: see 2.3. Undocumented.
- **Agent SDK / `-p --output-format stream-json`**: only for a process you start yourself (3.13).

### 5.2 Codex
- **Hooks** [DOC] https://learn.chatgpt.com/docs/hooks and [SRC] `codex-rs/protocol/src/protocol.rs` `HookEventName` (openai/codex 823ea83, 2026-10-05): PreToolUse, PermissionRequest, PostToolUse, PreCompact, PostCompact, SessionStart, SessionEnd, UserPromptSubmit, SubagentStart, SubagentStop, Stop, **Interrupt**. Locations: `~/.codex/hooks.json`, `[hooks]` in `~/.codex/config.toml`, `<repo>/.codex/`. "Hooks are enabled by default." stdin: `session_id, transcript_path, cwd, hook_event_name, model, permission_mode`, `turn_id` for turn hooks. Handler types in source: Command, McpTool, Prompt, Agent.
- **Legacy `notify`** [SRC] `codex-rs/hooks/src/legacy_notify.rs`: one payload type, `agent-turn-complete` (`thread-id, turn-id, cwd, client, input-messages, last-assistant-message`), JSON as last argv. Source has a TODO to remove it. So `notify` gives turn end only.
- **Rollout JSONL** [SRC] `codex-rs/rollout/src/policy.rs`: `TurnStarted` (serialised `task_started`), `TurnComplete` (`task_complete`), `TurnAborted` are persisted. `ExecApprovalRequest`, `ApplyPatchApprovalRequest`, `RequestUserInput`, `ElicitationRequest`, `ShutdownComplete` are in the not-persisted arm. **A rollout tail can tell working / done / aborted. It cannot tell "waiting for approval".**
- **app-server** [SRC] `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`: `ThreadStatus = NotLoaded | Idle | SystemError | Active { activeFlags: [WaitingOnApproval | WaitingOnUserInput] }`, pushed as `thread/status/changed`. This is the cleanest state model of any agent. A shared daemon exists (`codex app-server daemon ...`, control socket dir `app-server-control/app-server-control.sock`, marked experimental). [UNCONFIRMED] whether an outside client may attach and subscribe to threads it does not own.
- **TUI** [SRC] `codex-rs/tui/src/notifications/osc9.rs`: OSC 9 desktop notifications, with tmux passthrough wrapping.
- Thread writer lock `$CODEX_HOME/thread-writer-locks/<thread-id>.lock` held open by the live process (agent-deck [SRC]).

### 5.3 opencode
- [SRC] sst/opencode 907b3bc (2026-10-02): bus events `session.status` (`busy | retry | idle`), `session.idle`, `session.error`, `session.created`, `session.deleted`, `permission.asked`, `permission.replied`, `question.asked`, `question.replied`, `question.rejected`.
- Reach them by (a) a plugin file in `~/.config/opencode/plugins/` with an `event` handler (cmux, superset, tmux-agent-indicator), or (b) SSE `GET /event` on the HTTP server. agent-deck says the TUI binds a real server only with an explicit `--port`. [UNCONFIRMED] how to find the port of a TUI someone else started.
- Wire shape has changed over time (cmux comment). Accept both `session.idle` and `session.status`.

### 5.4 Gemini CLI
- [SRC] google-gemini/gemini-cli fb972b2, `packages/core/src/hooks/types.ts`: BeforeTool, AfterTool, BeforeAgent, Notification (`ToolPermission`), AfterAgent, SessionStart, SessionEnd, PreCompress, BeforeModel, AfterModel, BeforeToolSelection. Config in `~/.gemini/settings.json`.

### 5.5 Cursor CLI
- [DOC] https://cursor.com/docs/agent/hooks: sessionStart, sessionEnd, preToolUse, postToolUse, postToolUseFailure, subagentStart, subagentStop, beforeShellExecution, afterShellExecution, beforeMCPExecution, afterMCPExecution, beforeReadFile, afterFileEdit, beforeSubmitPrompt, preCompact, stop (`status: completed | aborted | error`), afterAgentResponse, afterAgentThought. `~/.cursor/hooks.json`. Docs say Cursor loads third-party (Claude Code) hooks; superset [SRC] confirms `cursor-agent` replays `~/.claude/settings.json`.
- [UNCONFIRMED] which events fire in `cursor-agent` versus the IDE. cmux and claude-caffeine install them for the CLI.

### 5.6 pi
- [SRC] badlogic/pi-mono 5b6c792, `packages/coding-agent/src/core/extensions/types.ts`: session_start, session_shutdown, before_agent_start, agent_start, agent_end, turn_start, turn_end, message_start, message_end, tool_call, tool_result, tool_execution_start, tool_execution_end, input, session_before_compact. Any `*.ts` in `~/.pi/agent/extensions/` is auto-loaded. No permission event (pi has no permission prompts by design).

### 5.7 Amp
- [SRC via cmux and superset] TypeScript plugin in `~/.config/amp/plugins/` with `amp.on("session.start" | "agent.start" | "tool.call" | "tool.result" | "agent.end")`, and a `thread.state` on newer versions.
- [UNCONFIRMED] in Amp's own docs. The manual page gave no content for this.

### 5.8 Factory droid
- [DOC] https://docs.factory.com/cli/configuration/hooks-guide: PreToolUse, PostToolUse, UserPromptSubmit, Notification (`permission_prompt, idle_prompt, auth_success, elicitation_dialog`), Stop, SubagentStop, PreCompact, SessionStart, SessionEnd. `~/.factory/hooks.json` or `hooks` key in `~/.factory/settings.json`. "Cancellation emits the informational Notification hook instead of Stop."

### 5.9 Grok, Antigravity, Copilot, Kiro, others
- [SRC via cmux catalog only] see 3.4. Not checked against each vendor's docs.

### 5.10 Agent Client Protocol (ACP)
- [SRC] agentclientprotocol/agent-client-protocol e73e560, `schema/v1/schema.unstable.json`: `session/update` variants `agent_message_chunk, agent_thought_chunk, tool_call, tool_call_update, plan, usage_update, subagent_update, ...`. Turn end = the `session/prompt` response with `stopReason` (`end_turn, max_tokens, max_turn_requests, refusal, cancelled`). Permission = `session/request_permission` request from agent to client.
- ACP is a stdio link between one client and one agent. An outside app cannot observe it.

---

## 6. Terminal-level signals

| Signal | Who uses it | Needs | Note |
|---|---|---|---|
| OSC title spinner (Claude) | agent-deck, herdr, AoE [SRC] | pty or tmux `pane_title` | Glyph set changed in Claude 2.1.228 (herdr manifest comment) |
| OSC 9 / 99 / 777 notification | Claude [DOC], Codex [SRC] | be the terminal | Only "done / needs you", only in some terminals, needs tmux passthrough |
| Bell | Claude `terminal_bell` [DOC] | be the terminal | Off by default |
| "esc to interrupt" regex | ccmanager, herdr, AoE, agent-deck, tmux plugins [SRC] | screen text | Hidden when a custom status line is set [DOC] |
| Permission prompt strings | claude-squad, ccmanager, herdr [SRC] | screen text | Changes with every UI release |
| Screen hash / stability | claude-squad, agentapi [SRC] | screen text | Working vs quiet only |
| pty output recency | vibetunnel (5 s) [SRC] | own the pty | Working vs quiet only |
| OSC 133 shell marks | none found for agent state | - | [UNCONFIRMED] no project used it for this |

A menu bar app owns none of these. Reach is limited to `tmux capture-pane` / `#{pane_title}` for tmux users, or the Accessibility API per terminal app. No project I read uses the Accessibility API.

---

## 7. Technique ranking (reliability for an outside observer)

| # | Technique | States | Latency | Install | Main failure |
|---|---|---|---|---|---|
| 1 | Agent-written state file (Claude `sessions/<pid>.json`) | busy / shell / waiting / idle / gone (pid) | poll or FSEvents, < 1 s | none | Undocumented; Claude only; `statusUpdatedAt` not refreshed in long turns |
| 2 | Lifecycle hooks / plugins + freshness + pid check | working / permission / idle / ended | instant | per-agent config | No hook on Esc (Claude), late Stop, crash, subagent and cross-agent noise |
| 3 | Agent event stream (opencode SSE, Codex app-server) | full, incl. approval | instant | none if reachable | Port or socket discovery; ownership |
| 4 | Session log tail (Codex rollout, Claude transcript) | working / done / aborted | file event | none | No approval state (Codex); pid-to-file mapping; background work |
| 5 | Screen rules + OSC title (manifests) | working / blocked / idle | 100 ms - 2 s | none, needs pty/tmux | UI drift; status line hides hints |
| 6 | Screen or pty activity | active / quiet | 2 - 5 s | none, needs pty | Silent long tools read idle |
| 7 | CPU + network per process tree | active / quiet / gone | 5 - 10 s + grace | none | Cannot see waiting; unrelated children; decay lag |
| 8 | Hook "touch" + long cooldown | recently active | - | hooks | Awake long after done |

---

## 8. What this means for Agent Caffeine

Contradictions with the current design:

1. **Transcript tailing is no longer the best Claude signal.** `sessions/<pid>.json` gives the state directly, covers interrupts, and gives the pid for free. Keep transcripts as a fallback for Claude < 2.1.119 [README] and for interrupt text.
2. **"Turn ended" is not "work ended".** After Stop, Claude can still run background agents, workflows, shells and monitors (`status: "shell"`; agent-deck #2473). A turn-based reader lets the Mac sleep in the middle of that work.
3. **CPU >= 3 % with a 2-minute grace cannot see "waiting for permission".** It also lags: agent-mode had to add a 30 s ignore window after an idle hook because `ps` %cpu decays slowly. Peers use 5 % plus network bytes, and demote CPU to a keep-alive once better signals exist.
4. **Do not expire a `busy` state by age.** Long tool calls produce no events. claude-caffeine's 300 s stale rule and tuiboard's 5-minute rule both produce false idle. Expire by pid death, with a long hard cap (awakebar 4 h, agent-mode 30 min heartbeat + CPU).
5. **One hold per session, not one global hold.** awakebar documents the bug: the first Stop releases the Mac while another session works.

Ideas worth taking:

- A. Read `~/.claude/sessions/*.json` first. `busy|shell` = hold. `waiting|idle` = release. Liveness by `kill(pid,0)` + `procStart`. (2026-10-11: `shell` = hold was wrong. See section 9.)
- B. A per-agent source ladder with freshness windows (agent-deck, AoE): reported state if fresh, else log tail, else CPU + network. Once an agent reports state, stop trusting CPU for it (agent-mode `hooked`).
- C. Optional hook install from one catalogue (cmux `AgentHookCatalog`): config path, format, events per agent. Claude HTTP hooks can post straight to the app. Codex `PermissionRequest` and `Interrupt` hooks fill the gap the rollout leaves.
- D. Codex passive path: `lsof` -> open rollout -> last of `task_started / task_complete / turn_aborted` (rorhcdream).
- E. `nettop` bytes_in per pid as a second passive signal for agents with no hooks (agent-mode).
- F. Filter noise: ignore hook events with `agent_id` (subagents), ignore Claude hooks fired under `cursor-agent`, ignore nested `codex exec` (superset).

Open questions to test on this Mac:

- Exact trigger for `status: "waiting"` in the Claude session file, and whether `shell` covers background agents and workflows or only shells.
- Whether desktop Claude / Codex apps write the same files.
- Whether an outside client can subscribe to the Codex app-server daemon.
- How to find the port of an opencode TUI not started with `--port`.

---

## 9. `shell` kept a Mac awake for a night: the record and the rule (2026-10-11)

### 9.1 What happened [LOCAL]

Measured from `pmset -g log` and from the state export of the app, on the owner's Mac, night of 2026-10-10 to 2026-10-11.

- The Mac was awake for 13.7 hours with the lid closed, on battery, in a bag. Charge 94 percent at 20:02, 46 percent at 09:45. The Mac was hot. The power log has no Sleep line in that time.
- Agent Caffeine held for the whole night. The assertion text was "Agent Caffeine: Claude Code is working", and the sleep flag was on.
- One Claude Code session had `status: "shell"` in `~/.claude/sessions/<pid>.json`. `statusUpdatedAt` was 20:47:18 and did not change again.
- The foreground turn was over. The owner saw "API error", because the network was gone.
- The session had one background shell task: a `zsh -c ...` child of the `claude` process, with `pnpm` below it (then `node` and `workerd`). It was a dev server that was left running.
- The whole tree was at 0.0 percent CPU. Two of its processes had 0.33 and 0.69 seconds of CPU time in 14 hours.
- The other children of the `claude` process were three `node` trees that started with the session: its MCP servers. They were at 0.0 percent too.
- The reader mapped `busy` and `shell` to working. The verdict was working, reason `reportsBusy`. A reported working has no time limit, so the hold had no end.

### 9.2 What `shell` means

`shell` is written when the turn ends and a background command of the session is still alive. It says nothing about work. A dev server, a `tail -f` and a `sleep 3600` all keep it. It ends when the last background command ends, or when the next turn starts. Section 2.3 and point 2 of section 8 read it as "work goes on". That is true only for a command that works.

`busy` is different. A turn can be silent for a long time and the file is not written again inside it. The rule "no staleness timeout on `busy`" stays.

### 9.3 The rule now

- The reader maps `shell` to idle with the flag `backgroundWork` ("the turn is over, background commands of this session still run"). `busy` is the only working.
- A busy child command holds the Mac, as after any turn that ended. Busy is the existing rule for a left-over command: at least 1 percent of a core (`VerdictRules.busyChildCPUFraction`) in both halves of 10 seconds (`EvidenceCollector.childWindow`). The reason is `runningCommand`.
- For `releaseAfterActivity` (300 seconds) after the turn ended (`statusUpdatedAt`) and after the last busy sample, the session still reads working. The reason is `backgroundWork`. This is for a build that is quiet between two steps.
- After that the session reads idle. The reason is `backgroundIdle`, with the minutes of quiet. The policy adds no release time of its own after it.
- A command that gets busy again makes the session working again, with the same 300 seconds after it.
- The child commands are the ones the census already counts: each top process below the agent that is no agent, engine or helper of the catalog. An MCP server is such a child. It is not taken out by name: at rest it is not busy, and when it is busy it holds an idle session too, by the rule that was there before.
- No output file is read. The process tree was enough for the record above.
- A recording from before this date has `working` with `over` for `shell`. It is read as idle with the flag, so it replays by this rule.

Tests: `VerdictTests` (the section "Background commands after the turn"), `LabReplayTests.testABackgroundCommandHoldsOnlyWhileItWorks` with `CaffeinagentTests/Recordings/synthetic-claude-background-shell.jsonl`, and `LabReplayTests.testAShellStatusOfThirteenHoursDoesNotHoldTheMac`.

### 9.4 Not measured

- Whether Claude Code also writes `shell` while a background agent or a workflow runs with no shell below it. Such work has no child process. With this rule it holds for 300 seconds after the turn and no longer. [UNCONFIRMED]
- A background command that waits without CPU use for more than 300 seconds and then works: `sleep 600 && make`, or a test that waits for a slow server. The Mac can sleep in the wait. This is the price of the rule.
- A dev server that uses 1 percent of a core or more at rest (a file watcher that polls). It holds without a limit, as it did before for an idle session.
- The time between the end of the turn and the write of `shell`.

---

## 10. A deleted version made working sessions invisible: the record and the fix (2026-10-12)

### 10.1 What happened [LOCAL]

Measured on the owner's Mac on 2026-10-12, with `proc_pidpath`, `proc_name`, `sysctl KERN_PROCARGS2` and the keys `pid`, `kind`, `status`, `procStart`, `startedAt` and `version` of the session files. No argument after argv[0] was printed.

- Two Claude Code sessions worked (`status: "busy"`) and Agent Caffeine had no row for them, in the menu and in a 12 second lab recording. The Mac could sleep while they worked. The owner saw it as "the app does not see subagents any more": one of the two ran his subagents.
- Claude Code installs each version as one binary that is named after the version: `~/.local/share/claude/versions/2.1.296`. `~/.local/bin/claude` is a link to the newest one. An update later deletes the files of old versions. On this Mac the files of 2.1.287, 2.1.294, 2.1.295 and 2.1.296 were there, and the delete was on 2026-10-10.
- Four processes of deleted versions ran: an interactive session of 2.1.286 from 2026-10-01 (busy), an interactive session of 2.1.289 from 2026-10-04 (idle), and a pty host of the daemon with its spare, both 2.1.289 from 2026-10-05. The spare had a job: its session file said `kind: "bg"`, `status: "busy"`, with a `jobId`.
- For each of the four, `proc_pidpath` gave length 0. For every process of a version whose file was there, it gave the versioned path.
- `proc_name` (`p_comm`) is the version number for all of them ("2.1.286"). It says nothing, for a deleted file and for a file that is there.
- `KERN_PROCARGS2` still gave the path each process was started with, then argv. For a session that path is the link, `~/.local/bin/claude`, and argv[0] is `claude`. For the pty host and the spare it is the versioned path, `.../claude/versions/2.1.289`, and argv[0] is the title (`claude bg-pty-host`, `claude bg-spare`), with the flag as argv[1].
- `ps -o comm` printed `claude` for all of them.

### 10.2 The cause

`SystemProcessCensus` left out every process for which `proc_pidpath` gave nothing. The comment said "a process that exited", and for a deleted binary that is wrong. So the catalog never saw these processes. The matchers themselves were right: argv[0] `claude` matches by name, and the title of a spare matches by the path that contains `/claude/versions/`.

The same fault was in `SystemProcessCensus.row(of:)`. The hook command walks up from its own pid with it, so a hook event of such a session found no agent above it.

This is no change of ours. Every Claude Code session that lived longer than the file of its version went out of sight on the day of the delete.

### 10.3 The fix

- The census takes the path from `KERN_PROCARGS2` when `proc_pidpath` gives nothing (`ProcessCensus.executable`). The row says so with `executableGone`. The path can be a link and the file can be gone, so nothing reads the file at that path: the catalog, `AgentHost`, the job probe and the hook command only compare the text.
- The evidence of an agent carries `executableGone` (`gone` in a recording), so the lab sees how many sessions run on a deleted binary.
- A second way, which needs no name and no path (`EvidenceCollector.adoptClaudeSessions`): a live process that no matcher knows, with a session file `~/.claude/sessions/<pid>.json` that fits its start time, is a Claude Code session. The evidence says `adoptedBySessionFile` (`adopt` in a recording). The file fits when `procStart` is the start of the process to 2 seconds, or when `startedAt` is not before it: a file that a crashed session left is older than every process that gets its pid later. The role is that of a spare, so a warm spare (the `spare` key and `status: "idle"`) stays out, as before. A process that a matcher knows keeps its match, also a helper.
- `procStart` is text in UTC, "Mon Oct  5 11:21:50 2026", the start of the process to the second. `startedAt` is in milliseconds and was 2 to 4 seconds after the start of the process, also for the spare that took its job later.
- The background session: a spare is matched by `--bg-spare` as `helperMaybeSession`, and the reader of the session file decides. With a job the file has `kind: "bg"` and a `jobId`, the status of the file is its state, and `~/.claude/jobs/<id>/state.json` adds the background job. With the path from the arguments a spare of a deleted version goes the same way.
- The catalog did not change, so its version stays 9.

Tests: `ProcessCensusTests` (the parser, `testExecutableComesFromTheArgumentsWhenTheFileIsGone`, and `testLiveSnapshotKeepsAProcessWhoseBinaryWasDeleted`, which deletes the binary of a process it started), `AgentCatalogTests.testAnAgentWhoseBinaryIsGoneStillMatches`, `EvidenceCollectorTests.testWorkingSessionsOfADeletedVersionAreSeenAndHold` and `testASessionFileMakesAnUnknownProcessASession`, `LabReplayTests.testSessionsOfADeletedVersionHoldWhileTheyWork` with `CaffeinagentTests/Recordings/synthetic-claude-deleted-version.jsonl`, and the test `DET-CC-21` of actest, which compares every live session file with the rows of the installed app.

### 10.4 The other agents

Every matcher reads the path of the census or argv. None reads the short name. So each agent had the same fault when an update deleted or replaced its binary while it ran, and the path from the arguments covers each of them. A binary that is moved and not deleted (an app in the Trash) keeps a path from `proc_pidpath`.

| Agent | Matched by | Binary deleted or replaced while it runs |
| --- | --- | --- |
| Claude Code session | argv[0] `claude` | Matches: argv[0], and the start path is the link `claude` |
| Claude Code spare and pty host | path contains `/claude/versions/`, title in argv[0] | Matches: the start path is the versioned path |
| Claude app | path ends in `Claude.app/Contents/MacOS/Claude` | Matches when it was started with its full path, as Launch Services does |
| Claude Code of the Claude app | path ends in `claude.app/Contents/MacOS/claude`, in a versioned folder that the app also deletes | Matches: the app starts it with its full path. Else its session file adopts it, as a Claude Code |
| Codex CLI | name `codex` from argv[0], a script or the path | Matches |
| Codex managed daemon | name `codex` and `app-server --managed-daemon` | Matches |
| Codex desktop engine | path ends in `codex-cli/CodexCLI.app/Contents/MacOS/codex` and `app-server` | Matches when started with its full path |
| Cursor and its helpers | path in `Cursor.app/Contents/...` | Matches when started with their full paths, as Electron does |
| Antigravity engine | path ends in `Antigravity.app/Contents/Resources/bin/language_server` | Matches when started with its full path |
| opencode, Droid, and the CLIs matched by name | name from argv[0] or the path | Matches |
| Pi, Gemini CLI, OpenClaw session | name of the script that `node` or `bun` runs | Matches: the script name is in argv. The interpreter is read from argv[0] or the start path |
| OpenClaw gateway | title `openclaw-gateway` in argv[0] | Matches |
| Grok Build | name `grok`, or path contains `/.grok/downloads/grok-` | Matches: started through the link `~/.grok/bin/grok` or with the download path |
| Hermes Agent | source of `python -c` in argv | Matches when argv[0] or the start path names Python |

Not measured for any agent but Claude Code: that its updater deletes the binary of a running process, and what start path its processes have then. [UNCONFIRMED] The rows above are from the code and from the start paths in the earlier notes.

### 10.5 Not covered

- A process with no path from `proc_pidpath` and no readable arguments is still left out. For a process of the user, the arguments were readable in every case seen.
- A census that read the path before the file was deleted keeps the resolved path and does not say `executableGone` until the app starts again. The match is the same.
- Only Claude Code has the second way. The other agents write no file that names their pid, but for the hooks.
- A session file of a version before `startedAt` and `procStart` adopts nothing.
