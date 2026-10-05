# 04 - Experiments: measured signals per agent

Date: 2026-10-05, 14:49 to 15:15 local. Machine: this Mac (Darwin 25.6.0).
Method: read-only sampling. `sample.py` reads `ps`, `lsof -iTCP`, `pmset -g assertions` and file mtimes once per second.
All CPU numbers are "percent of one core", computed from CPU-time deltas (the same method as the app).
"tree" = the process plus all descendants.

Helper scripts in this folder: `sample.py` (tree + observe modes), `run.sh` (headless run + sampler), `ptyrun.py` (TUI in a private pty, no window), `stats.sh`, `compact.sh`, `ptysum.sh`, `obsstats.py`.
Raw data: `run-*.tsv`, `pty-*.tsv`, `observe-1s.tsv` (180 s), `observe-5s.tsv` (420 s, same 5 s interval as the app).

## 0. What I ran (cost)

| Label | Command | Model calls | Result |
|---|---|---|---|
| claudeA | `claude -p --model sonnet --allowedTools Bash "<sleep 20, then 250 words>"` | 1 turn, 2 requests | ok, 32 s |
| claudeB (x2) | `claude` TUI in private pty | 0 (first try exited at trust prompt; second sat idle at the prompt) | idle data only |
| claudeC | `claude` TUI in private pty, prompt typed into my own pty | 1 turn, 2 requests | ok |
| claudeD | `claude` TUI, 14 s, no prompt, title env var unset | 0 | OSC check |
| codexA | `codex exec --skip-git-repo-check "<same prompt>"` | 1 turn | ok, 46 s |
| codexB | `codex "<sleep 15, 120 words>"` TUI in private pty | 1 turn | ok |
| codexC | `codex` TUI, 12 s, no prompt | 0 | daemon reuse check |
| opencodeA | `opencode run "<same prompt>"` | 1 turn | ok, 61 s |
| droidA | `droid exec --auto low ...` | 0 | failed: not signed in |
| grokA | `grok --always-approve -p ...` | 0 | failed: not signed in |
| pi | - | 0 | no `pi` binary on this Mac (`~/.pi/agent` holds only `bin/fd`, `bin/rg`, a 2-byte auth file, an MCP cache) |

Every run used a fresh `mktemp -d` directory. All of them are removed.

## 1. Process identity

### Claude Code (2.1.286 to 2.1.289)

- `ucomm` is the VERSION STRING (`2.1.289`), not `claude`. The match works only through the basename of argv[0] (`claude`). Measured on all 12 sessions.
- Interactive session: `claude --dangerously-skip-permissions`, parent `-zsh`, has a tty (`ttys001`...).
- Headless: `/Users/.../.local/bin/claude -p ...`, no tty.
- Daemon family, all under `/tmp/cc-daemon-501/<id>/` (unix sockets `control.sock`, `spare/<id>.pty.sock`, `spare/<id>.claim.sock`):

```
claude --dangerously-skip-permissions (pid 93968, ttys009, interactive session)
  └ claude daemon run --origin transient --spawned-by {...}      (20909, no tty)   supervisor
      ├ claude bg-pty-host --bg-pty-host .../025596a1.pty.sock ... (20930, no tty)  pty owner
      │   └ claude bg-spare --bg-spare .../025596a1.claim.sock    (20946, ttys013) CLAIMED: a real background agent session
      │       ├ caffeinate -i -t 300
      │       └ zsh -c ... (tool calls)
      ├ claude bg-pty-host ... e5f57e77 (21176)
      │   └ claude bg-spare ... e5f57e77 (21189, ttys014)  UNCLAIMED warm spare, session file says spare + idle
      └ claude bg-pty-host ... 17dea89c (21510)
          └ claude bg-spare ... 17dea89c (21523, no tty)   UNCLAIMED, no session file yet
```

- What they are: `bg-spare` is a pre-started Claude Code process. When a background job starts (`claude --bg`, or a background subagent of an interactive session), the daemon hands the job to a spare. The argv does NOT change after the claim. So `claude bg-spare ...` is sometimes a real working session and sometimes an idle spare.
- The `bg-spare` with 24 percent CPU was pid 20946. It is a claimed spare. It is the session that ran this experiment (my own shell's parent chain: zsh -> 20946 -> 20930 -> 20909 -> 93968). `~/.claude/sessions/20946.json` says `kind: "bg"`, `status: "busy"`. So the CPU was real agent work. It is not a false positive.
- CPU, 5 s windows, 420 s: unclaimed spare 21189 tree min 0.0 / med 0.2 / p90 0.4 / max 7.5 (1 window of 82 over 3 percent). Spare 21523: max 0.2. `bg-pty-host` alone: root max 0.6. `daemon run` alone: root max 0.6.
- Matcher today: all of `daemon run`, `bg-pty-host`, `bg-spare` match (argv[0] basename = `claude`). Because the app sums descendants, the SAME work is counted on 5 roots: the claimed spare, its pty-host, the daemon, and the interactive session 93968 that started the daemon (its own status file said `idle` for all 82 windows while its tree showed median 205 percent). That is not a wrong keep-awake decision, but the app's "which agent is working" view is wrong and it shows 3 to 4 phantom agents.
- How to tell a claimed spare from a warm one: `~/.claude/sessions/<pid>.json` (keys `kind`, `status`, `spare`, `jobId`). Warm spare has `spare` key and `status: idle`.

### Codex CLI (0.159.2) and Codex desktop (inside ChatGPT.app)

- CLI: `ucomm` = `codex`, binary `~/.local/bin/codex` -> `~/.codex/packages/standalone/current/bin/codex`.
- `codex exec`: one process plus children `node .../cua-repl.mjs`, 2x `node_repl`, `codex-code-mode-host`, and the tool command.
- Interactive `codex` TUI starts a managed daemon:
  - `~/.codex/packages/app-server-daemon/releases/0.159.2-.../bin/codex app-server --listen unix:// --managed-daemon`
  - `.../codex app-server daemon pid-update-loop`
  - Both have `ucomm` = `codex`. They are children of the TUI at first. After the TUI exits they STAY ALIVE with ppid 1. Measured: they were alive 75 s after my TUI exited. I stopped them (they were mine).
  - A second TUI reuses the daemon. Measured (codexC): the second TUI tree had exactly 1 process for 12 s; no new daemon appeared.
  - The tool command (`sleep 15`), `codex-code-mode-host` and `node_repl` were in the daemon's subtree (measured in codexB, tree n=8).
- Desktop: parent `ChatGPT` (pid 25328) -> `codex -c features.code_mode_host=true app-server --analytics-default-enabled ...` (25445), `codex app-server --listen stdio://` (27648, parent is a `node_repl`), `codex exec-server --remote https://codex-cloud-environments.chatgpt.com/api ...` (29747). Path is inside `ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`. Idle CPU over 420 s: 25445 max 0.2, 27648 max 0.2, 29747 max 0.2, `ChatGPT` tree 0.4/1.2/2.2 (min/med/max).
- Control files: `~/.codex/app-server-daemon/daemon.pid` (keys `pid`, `processIdentity`, `processStartTime`, `executableIdentity`), `~/.codex/app-server-control/app-server-control.sock` -> `/private/tmp/codex-daemon-501/<hash>`, `~/.codex/ipc/ipc.sock`.

### opencode

- `~/.opencode/bin/opencode run ...`: ONE process for the whole run. No helper children except the tool command (`sleep`). `ucomm` not recorded by my sampler; assumed `opencode` from the binary name.

### Antigravity (2.19.1, installed today 13:40)

- `Antigravity` (99153) -> `language_server --standalone --override_ide_name antigravity --subclient_type hub ... --api_server_url https://generativelanguage.googleapis.com --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com --enable_sidecars --host_bridge_url=http://127.0.0.1:49602 ...` (99271). `ucomm` = `language_server`, path `/Applications/Antigravity.app/Contents/Resources/bin/language_server`.
- Listens on 127.0.0.1:49603 and :49604 (language_server), :49601 and :49602 (Antigravity main).
- Idle CPU over 420 s (5 s windows): language_server 0.0/0.0/0.4, Antigravity tree 1.2/1.6/2.2, renderer 1.2/1.6/2.0.
- Today's matcher cannot see it: the name is not in the allowlist and the path is inside `.app/Contents/`. I could not produce a working state (no screen driving), so working CPU is NOT measured.

### droid, grok, pi, T3 Code, Vibe Island

- droid: `~/.local/bin/droid` (88 MB single binary). Only start-up measured (36.6 percent for 1 s, 2 TCP connections).
- grok: `~/.local/bin/grok` -> `~/.grok/bin/grok`. Exits in 1 s. Has `--leader-socket` (default `~/.grok/leader.sock`) and `-p` headless mode.
- pi: not installed.
- T3 Code: not running. Data dir `~/Library/Application Support/t3code`. Not tested.
- Vibe Island: not running. See section 8.
- herdr: `herdr server` (pid 2483) is the terminal multiplexer that owns the interactive sessions. Not an agent. `ucomm` = `herdr`, not in the allowlist, so no false match.

## 2. CPU

### Controlled runs (1 s samples, tree percent: min / median / max, mean, share of samples >= 3)

| Agent, mode | Start-up peak | Tool running (`sleep`) | Waiting for model / streaming | Idle at prompt |
|---|---|---|---|---|
| claude -p | 113 (hooks + MCP start) | n=18: 0.0 / 0.9 / 3.7, mean 0.91, 5% | stream n=6: 0.0 / 0.0 / 2.8, mean 0.77, 0% | - |
| claude TUI | 105 | n=13: 1.9 / 2.8 / 7.5, mean 3.52, 46% | stream n=5: 0.9 / 1.9 / 6.5, mean 3.36, 40% | n=40: 0.0 / 0.0 / 9.4, mean 0.69, 5%; second run n=66: 0.0 / 0.0 / 8.4, mean 0.65, 3% |
| codex exec | 48 | n=18: 0.0 / 0.0 / 3.8, mean 0.36, 5% | 14 s wait + answer, n=12: 0.0 / 0.0 / 0.9, mean 0.23, 0% | - |
| codex TUI (+ daemon child) | 74 | n=11: 0.0 / 0.9 / 4.7, mean 1.19, 9% | n=7: 0.9 / 1.9 / 2.8, mean 1.74, 0% | n=28: 0.0 / 0.0 / 0.9, mean 0.06, 0% |
| opencode run | 125 | n=18: 0.0 / 0.9 / 2.8, mean 0.71, 0% | wait n=6: 0.0 / 0.9 / 2.8; STREAM n=15: 11.2 / 13.1 / 20.6, mean 14.55, 100% | - |

Same data as 5 s sliding windows (what the app sees), share of windows >= 3 percent:

| Phase | windows | min | max | >= 3% |
|---|---|---|---|---|
| claude -p, tool running | 14 | 0.5 | 1.5 | 0% |
| claude TUI, tool running | 9 | 3.0 | 4.3 | 100% (spinner animation; margin is 0.0 to 1.3 points) |
| codex exec, tool running | 14 | 0.0 | 1.3 | 0% |
| codex exec, waiting for model | 8 | 0.0 | 0.4 | 0% |
| codex TUI, tool running | 7 | 0.6 | 1.9 | 0% |
| opencode, tool running | 14 | 0.4 | 1.1 | 0% |
| opencode, streaming text | 11 | 14.2 | 15.1 | 100% |
| claude TUI idle | 62 | 0.0 | 2.2 | 0% |

### Existing sessions, with Claude's own status file as ground truth (`~/.claude/sessions/<pid>.json` `.status`)

5 s windows, 420 s, 10 interactive sessions + spares:

- status `busy` (pids 2422 and 84496, 20 windows): tree 2.0 to 12.2, median 3.2 to 3.9. 45 percent of busy windows are UNDER 3 percent.
- status `idle` (752 windows over 10 processes): median 0.4, p90 0.6, max 10.7. 19 windows (2.5 percent) are at or over 3 percent. They came from 10 different processes. Largest gap between two such spikes: 183 s. Most spikes were in one 70 s cluster.
- status `waiting` (pid 2422, 48 windows = 240 s): 0.2 / 0.6 / 5.3. 6 percent of windows over 3.
- Threshold sweep, 5 s windows: 1% -> flags 7.4% of idle windows, misses 0% of busy. 2% -> 4.9% / 0%. 3% -> 2.5% / 45%. 5% -> 2.0% / 75%. 10% -> 0.1% / 95%.
- Same sweep, 1 s windows: 3% flags 2.5% of idle and misses 66% of busy.
- Note: n is small for busy (20 windows of 5 s, 91 samples of 1 s). The direction is clear, the exact percent is not.

### Answers

- Is 3 percent good? No. It sits inside the overlap. Busy interactive Claude runs at 2 to 4 percent while it waits for a tool or the model. Headless Claude, Codex (both modes) and opencode sit at 0 to 1 percent in the same states.
- Does a streaming response alone cross it? opencode: yes (13 percent). Claude TUI: borderline (mean 3.4). Claude headless: no (0.8). Codex: no (0.2 to 1.7).
- Does waiting for a slow model fall under it? Yes for every agent measured. Codex exec stayed at 0.0 to 0.9 for 14 s with an open request.
- A long tool call with low CPU (`sleep`, a network wait, a remote build, `gh run watch`) is invisible to CPU for all agents except the Claude TUI, and that one passes only because of its spinner.

## 3. Child processes

| Agent | Tool call = child process? | Shape | Lifetime |
|---|---|---|---|
| claude | yes for Bash | `zsh -c ...` -> `sleep 20` | exactly the tool duration (20 s seen as 19 to 20 samples). MCP servers (`node ... mcp`) live for the whole session and are not tool calls. Hooks appear as short `node`/`sh` children at start and around tools. |
| codex | yes | `sleep 20` under `codex-code-mode-host` side; plus permanent `node_repl` x2, `cua-repl.mjs` | tool duration. In TUI mode the child belongs to the managed daemon. |
| opencode | yes | `sleep 20` direct child | tool duration |
| all | no child while: waiting for the model, streaming, file read/edit tools, web fetch, MCP tool calls (these run inside long-lived MCP children) | | |

A child process is a good "tool is running" signal for shell tools. It says nothing about model wait.

## 4. Session files

### Claude Code

- Transcript: `~/.claude/projects/<cwd with / replaced by ->/<session-uuid>.jsonl`. JSON lines. Keys used: `type`, `subtype`, `timestamp`, `message.role`, `message.stop_reason`, `message.content[].type`, `attachment.type`.
- Write rhythm (claudeA, headless): write at turn start (t=2.2), at the tool_use record (t=4.3), then NOTHING for 20.4 s while the tool ran, write at tool_result (t=24.7), NOTHING for 6.4 s while the model answered, write at the end (t=31.1). The assistant record is written once per message, not per token. So the gap between writes = tool duration or model duration. A 10-minute build gives a 10-minute silent transcript.
- Markers: turn start = `type:user` with string content. Tool call = `type:assistant`, `stop_reason:tool_use`. Tool done = `type:user` with `tool_result` content. Turn end = `type:assistant` with `stop_reason:end_turn`, then `type:system subtype:stop_hook_summary` and `subtype:turn_duration`. "Open tool_use without tool_result" = tool still running. Permission wait: not produced (all sessions here run with skip-permissions).
- `--bare`/child sessions: an interactive `claude` started from inside another Claude session inherits `CLAUDE_CODE_CHILD_SESSION` and prints "Transcript saving is off". Measured: claudeB wrote no jsonl. So nested interactive sessions are invisible to the transcript tail. (`claude -p` from the same environment did write one.)
- `~/.claude/sessions/<pid>.json`: ONE FILE PER LIVE PROCESS, removed at exit. Keys: `pid`, `procStart`, `sessionId`, `cwd`, `kind` (`interactive` | `bg`), `entrypoint`, `status`, `statusUpdatedAt`, `updatedAt`, `waitingFor`, `name`, `version`, `messagingSocketPath` (`/tmp/cc-socks/<pid>.sock`), plus `jobId`, `spare`, `parkedJobId` for daemon cases.
  - `status` values seen: `idle`, `busy`, `waiting`. Measured: claudeA went null -> `busy` 2 s after start and stayed `busy` for all 29 s including the 20 s sleep and the model wait. claudeC: file changed at turn start and turn end. Session 2422 showed `waiting` for 240 s (waiting for the user; `waitingFor` holds the reason; I did not read its value).
  - This is the best single signal for Claude Code. It also exists for `-p` runs and for claimed spares.
- `~/.claude/jobs/<id>/state.json` (background jobs): key `state` with values `working`, `blocked`, `done`; also `inFlight`, `tempo`, `updatedAt`. `timeline.jsonl` logs each state change (my job: 24 x working, 12 x blocked, 2 x done).
- `~/.claude/daemon.status.json`: keys `supervisorPid`, `supervisorProcStart`, `writtenAt`. Daemon liveness only. `~/.claude/daemon/roster.json`: `workers.<id>.{cwd, cliVersion, dispatch.*}`: worker list, no busy flag. `~/.claude/state/`: only an MCP cache. Not useful.

### Codex

- Rollout: `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`. Keys `timestamp`, `type`, `payload.type`, `payload.role`, `payload.status`, `payload.name`.
- Markers: turn start = `event_msg` / `task_started`. Tool call = `response_item` / `custom_tool_call` (name `exec`). Tool done = `custom_tool_call_output`. Turn end = `event_msg` / `task_complete`. Also `token_count`, `item_completed`, `turn_context`.
- Rhythm (codexA): writes at 0, 2, 6, 7, 10, 14 s; then silent 14.3 s during the tool; write at tool output; silent 14.3 s during the model answer; final writes + `task_complete`. In 7 desktop sessions: 29 `task_started`, 29 `task_complete`: balanced, so "started without complete" = turn in progress.
- `~/.codex/thread_history_1.sqlite`, table `thread_turns` with `status` (`completed`, `interrupted`, `failed`), `started_at`, `completed_at`. `state_5.sqlite` table `threads` has `updated_at_ms`, `rollout_path`. The `-wal` files change on every event (seen at each rollout write).
- Desktop app-server keeps the rollout files and `~/.codex/thread-writer-locks/<uuid>.lock` open (10 lock files open now). `lsof -p <app-server>` lists which threads are loaded, not which are busy.
- Permission wait: not produced (bypass mode). Hook `PermissionRequest` exists in `~/.codex/hooks.json`.

### opencode

- `~/.local/share/opencode/opencode.db` (+ `-wal`, `-shm`), tables `session`, `message`, `part` (JSON in `data`). `storage/` now holds only `migration` and `session_diff`; the DB is the source of truth. Log: `~/.local/share/opencode/log/opencode.log`.
- Markers in `part.data`: `type: step-start`, `type: tool` with `state.status` (`completed`; `running` while active, assumed from the 23.4 s `time_updated - time_created`), `type: step-finish` with `reason: tool-calls | stop`. In `message.data`: `finish`, `time.completed`.
- Rhythm: `-wal` grew at t=1, 3, 7, 12, 13, 16 s, then silent 20 s during the tool, then at 36.6, 42, 44 s. During the 15 s text stream the `-wal` size did not change (text part updated in place; mtime polling on size missed it).

### Antigravity

- `~/.gemini/antigravity/`: `conversations/` (1 file, 131072 bytes), `conversation_summaries.db` (20480 bytes, held open by language_server), `agyhub_summaries_proto.pb`, `brain/`, `annotations/`, `scratch/`.
- `antigravity_state.pbtxt` (848 bytes): only `migrations`, `seen_nuxs`, `post_onboarding`, `installation_uuid`, `agent_onboarding_completed`. No session state.
- Write rhythm while working: NOT measured (cannot trigger a task).

### droid, grok, pi, T3

- droid: `~/.factory/sessions/<cwd-slug>/<uuid>.jsonl` (first record keys `type`, `id`, `cwd`, `title`, `sessionTitle`, `owner`, `version`) + `<uuid>.settings.json` (`assistantActiveTimeMs`, `autonomyMode`, `model`, `reasoningEffort`). `~/.factory/background-processes.json` = `{"processes": []}`. `~/.factory/logs/droid-log-single.log`. Working rhythm not measured.
- grok: `~/.grok/sessions/<url-encoded cwd>/<uuid>/{events.jsonl, chat_history.jsonl, plan_mode.json, ...}`, `~/.grok/active_sessions.json` (2 bytes = empty now; the name says it lists live sessions; not verified), `~/.grok/logs/unified.jsonl`. Working rhythm not measured.
- pi: no session directory exists.
- T3 Code: not inspected beyond the data dir name.

## 5. Network

- `lsof -nP -a -iTCP -p <pid>` works without root for own processes.
- Claude: IDLE sessions keep 1 ESTABLISHED TLS connection to 160.79.104.10:443 (= `api.anthropic.com`, checked with `dig`). 7 of 7 idle sessions and the warm spare had exactly 1. Busy sessions had 2 and 4. My fresh runs held 15 to 17 connections from start to exit, idle or not. So "has a connection to the API" is NOT a turn signal. Connection count is weak.
- Codex: 4 to 5 connections to Cloudflare addresses (104.18.32.47, 172.67.190.225) for the whole run. Desktop app-server idle: 1. opencode: 7 for the whole run. Antigravity language_server idle: 3 remote + 1 local.
- All vendors sit behind shared CDN addresses. Address matching would be fragile.
- `nettop -P -L 1 -J bytes_in,bytes_out -p <pid>` works without root, but one call takes 5.05 s wall time. Idle session: 0 bytes in 33 s, then one 10 kB burst. Busy sessions: counters move every sample. Counters are not monotonic (they drop when a connection closes). Verdict: usable only as a long-running stream, noisy, last resort.

## 6. Power assertions

- Claude Code takes its own assertion. It spawns `caffeinate -i -t 300` as a direct child.
  - claudeC (TUI): `caffeinate` appeared at turn start (t=15), turn ended at t=35.4, `caffeinate` gone at t=65 = 30 s after turn end.
  - Live sessions at 15:11: every `busy` session had one (2422, 23135, 20946); no `idle` session had one. It is re-spawned before the 300 s timeout (I saw pids 32924, 46965, 53862 in turn under 20946).
  - The 300 s `caffeinate` seen earlier today (pid 32924) had parent 20946 = the claimed `bg-spare` = the session running this experiment.
  - `claude -p` did NOT spawn it (claudeA: no assertion in 32 s).
  - It is `-i` only: `PreventUserIdleSystemSleep`. It does not stop lid-close sleep.
- Codex exec, Codex TUI, opencode: no assertion and no `caffeinate` in any sample.
- Antigravity, ChatGPT/Codex desktop: no assertion while idle. Working state not measured.
- So "a `claude` process has a `caffeinate -i -t 300` child" = Claude Code is in a turn (or ended one under 30 s ago). Cheap: it is already in the `ps` output.
- `pmset -g assertionslog` is a live stream that never ends. Do not call it without a timeout.

## 7. Terminal signals

- Claude TUI: no OSC title sequence captured. Caveat: my environment sets `CLAUDE_CODE_DISABLE_TERMINAL_TITLE`, which was inherited in the working run (claudeC). With the variable unset (claudeD, idle only, 14 s) there was still no OSC. The variable's existence shows the feature exists. Working-state title: NOT measured.
- Codex TUI: only OSC 10 / OSC 11 colour queries at start. No title.
- pty output rhythm (my own pty): Claude TUI while working ~47 to 52 chunks per 5 s (spinner), 0 to 1 while idle. Codex TUI ~150 chunks per 5 s while working, 0 while idle. An outside app cannot read another terminal's pty, so this is not usable.
- Vibe Island writes titles itself (`\x1b]2;<title>\x07` to the tty, cache in `~/.vibe-island/cache/osc2-titles/`). It uses titles to find the terminal tab, not to detect work.

## 8. Other things: hooks, sockets, status files

- Hooks are the strongest push signal, and they are already installed here by two other tools:
  - Vibe Island: every Claude hook event (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`, `SessionEnd`, `TeammateIdle`) runs `~/.vibe-island/bin/vibe-island-bridge --source claude`. The same bridge is in `~/.codex/hooks.json` (10 events), `~/.factory/settings.json`, `~/.grok/hooks/vibe-island.json` (11 events), `~/.cursor/hooks.json`, and as an opencode plugin `~/.config/opencode/plugins/vibe-island.js` (listens to `session.status` / `session.idle`). The bridge forwards hook JSON to the app over a unix socket (`/tmp/.vi-<hash>.sock` per the binary strings). Binary strings also show a "Codex rollout fallback" and pi events `tool_approval_requested` / `tool_approval_resolved`. So Vibe Island = hooks first, rollout files second, `ps` only to find the tty.
  - herdr: `SessionStart` hook reports `session_id` + `transcript_path` to its socket (`HERDR_SOCKET_PATH`).
- Claude sockets: `/tmp/cc-socks/<pid>.sock` (messaging, token-protected), `/tmp/cc-daemon-501/<id>/control.sock`. Not probed.
- Codex sockets: `/private/tmp/codex-daemon-501/<hash>`, `~/.codex/ipc/ipc.sock`. Not probed.
- Claude statusline command receives JSON on every assistant message (Vibe Island uses it for rate limits). Possible push channel, interactive only.

## 9. Our own app

- `caffeinagent` pid 9735: 86.97 s CPU in 68 min 05 s = 2.1 percent of one core on average. 5 s windows: 1.6 / 2.8 / 7.5 (min / med / max). RSS 130 MB. No child processes at sample time.
- Holds two assertions, both named `caffeinagent: agentWorking`: `PreventUserIdleSystemSleep` and `PreventSystemSleep`. Held without a break for 57 min at 15:11 (many sessions were really busy in that time, mine included).

## 10. False positives and false negatives proved for today's rules

False negative (app says idle, agent works):
1. Codex exec during a 20 s tool call: 5 s windows max 1.3 percent. During a 14 s model wait: max 0.4.
2. Codex TUI during a tool call: 5 s windows max 1.9.
3. Codex TUI when the managed daemon already exists: the TUI process tree is 1 process; work is in `codex app-server --managed-daemon` (ppid 1), which the rule ignores. Measured: reuse of the daemon and the 1-process tree. Inferred: that all work then lands in the daemon.
4. opencode during a tool call (max 1.1) and during model wait (max 2.8 on 1 s samples).
5. `claude -p` during a tool call (max 1.5) and during streaming (max 2.8 on 1 s samples).
6. Real busy interactive Claude sessions: 45 percent of busy 5 s windows under 3 percent. The Claude TUI passes during tool waits only thanks to its spinner (3.0 to 4.3).
7. Transcript tail: silent for the full tool time and the full model time (20.4 s and 6.4 s measured; scales with the tool). Nested interactive Claude sessions write no transcript at all.
8. Antigravity: no rule can match it (name + `.app/Contents/` path). Not measured in a working state.
All of 1 to 6 are covered by the 2-minute grace only when the quiet phase is shorter than 2 minutes. I did not run a quiet phase longer than 20 s.

False positive (app says working, nobody works):
1. Idle Claude sessions spike: 2.5 percent of idle 5 s windows reach 3 to 10.7 percent. 10 idle processes gave 19 such windows in 420 s. Each one starts a 2-minute grace. In this sample the longest spike-free gap was 183 s, so the Mac could sleep, but not by much.
2. Session status `waiting` (waiting for the user): 6 percent of windows over 3 percent.
3. Agent start-up always crosses (48 to 125 percent) even when no prompt is sent.
4. Phantom agents: `claude daemon run`, `claude bg-pty-host`, the parent interactive session all show the claimed spare's CPU as their own. Count is wrong, decision is right.
5. Leftover Codex daemon (`codex app-server --managed-daemon`, ppid 1): ignored by the rule today, so no false positive now. If the rule is relaxed to fix false negative 3, the idle daemon must not count (idle CPU 0.0 to 0.2 on the desktop one).

Not a false positive: `claude bg-spare` at 24 percent. It was a claimed spare doing real work.

## 11. Side effects of this experiment (tell the owner)

- `droid exec` changed `~/.factory/settings.json` by itself: it imported the Claude Code hooks (new keys `hooks.claudeHooksImported: true` and `hooks.importedClaudeHooks`, file grew from about 2078 to 6538 bytes). It also created `~/.factory/{certs,logs,updates,sessions,temp,background-processes.json}`.
- The interactive Codex run started the managed Codex daemon. I stopped both daemon processes (48605, 48631).
- Hooks of other tools fired on my runs. They are the owner's normal hooks.

## 12. Measured versus assumed

Measured: everything with a number above; process trees; file markers; assertion owners; daemon reuse.
Assumed or not measured: working-state CPU, files, network and assertions for Antigravity, Codex desktop, ChatGPT, T3 Code, droid, grok, pi; permission-wait records for every agent; Claude title OSC while working; opencode `state.status: running`; `ucomm` of opencode/droid/grok; quiet phases longer than 20 s; that a second Codex TUI runs its tools inside the shared daemon.
