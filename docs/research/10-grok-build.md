# 10 - Grok Build: how to detect working, waiting, idle

Date: 2026-10-08. Mac of the owner. `grok 0.2.111 (94172f2aa4e5) [stable]`, installed by xAI's own installer in `~/.grok`.
No prompt was sent and no model was called. Nothing was written below the owner's `~/.grok`. Of the owner's session files
only structure was read: file names, sizes, write times, JSON keys, and the values of type, phase, outcome, decision and
tool name fields. `auth.json` and `agent_id` were not opened.

Marks: [DOC] the docs Grok Build installs (`~/.grok/README.md`, `~/.grok/docs/user-guide/*.md`) and `grok --help`.
[MAC] measured on this Mac. [BIN] strings of the installed binary. [TMP] measured with the real binary and a home folder
of its own in `/tmp` (`HOME=<tmp>`), with no account. [INFERRED] not proven. [UNKNOWN] must be measured live.

## 0. Result

Grok Build has both: an exact state on disk that needs no install, and hooks.

1. Each session writes `~/.grok/sessions/<encoded cwd>/<session id>/events.jsonl`. It holds `turn_started`,
   `turn_ended`, `permission_requested` and `permission_resolved` with a time each. `GrokEventsReader` reads it, and
   Grok Build is a `.state` agent while a log of its process is found.
2. Hooks are JSON files in `~/.grok/hooks/`. Our entries go into a file of our own, `agent-caffeine.json`. They are the
   second source: for a session whose log cannot be tied to its process.

## 1. The product and the process [MAC] [DOC]

- The name is "Grok Build": `01-getting-started.md` ("Grok Build is a terminal-based AI coding assistant"), `grok --help`
  ("Grok Build TUI"), and the first-run dialog in the binary. The title of `README.md` is "Grok".
- `~/.local/bin/grok` -> `~/.grok/bin/grok` -> `../downloads/grok-macos-aarch64` (Mach-O arm64). `~/.grok/bin/agent` is a
  link to the same file, and `agent --help` prints the same help with `Usage: agent`.
- [TMP] One running TUI is one process: argv[0] `/Users/<user>/.grok/bin/grok`, executable (the `txt` line of `lsof`)
  `~/.grok/downloads/grok-macos-aarch64`. No child process at the prompt.
- [MAC] In the owner's `~/.grok/logs/unified.jsonl` (keys `ts, lvl, msg, pid, src, sid, ctx, ver`) one pid wrote the lines
  of `src: "shell"` (the agent) and of `src: "grok-pager"` (the TUI) for the one session with a `sid`. So the agent and
  the TUI were one process, and no separate daemon ran that session.
- [DOC] `grok --help` lists the commands `agent` (run without the UI), `completions`, `dashboard`, `doctor`, `export`,
  `help`, `inspect`, `leader`, `login`, `logout`, `mcp`, `memory`, `models`, `plugin`, `sessions`, `setup`, `trace`,
  `update`, `version` (`v`), `worktree`, `wrap`. `-p` is a headless single turn.
- [DOC] [BIN] A "leader" exists: `--leader-socket` (default `~/.grok/leader.sock`), `grok leader list|info|kill`, and
  "Spawned leader subprocess" in the binary. [MAC] No `leader.sock` was in `~/.grok` and no leader process ran with the TUI
  at its prompt. [UNKNOWN] when a leader runs, what its argv is, and whether tool commands are then its children.
- [UNKNOWN] Tool commands as children of the `grok` process: not seen, no turn was run. The hooks run as `sh -c <command>`
  ([BIN] `sh`, `-c` next to "failed to spawn command").
- [DOC] `[ui.notifications] sleep_prevention = true` is the default: "prevent display sleep during agent turns". So Grok
  Build takes a power assertion of its own during a turn. [UNKNOWN] its type and when it is given up.

Catalogue (`AgentCatalog`, version 7): the definition `grok`, name "Grok Build", matched by the name `grok` and by the
path `/.grok/downloads/grok-` (so the `agent` link is the same agent). A process whose first argument is one of the
management commands above is no agent. `agent` and `dashboard` are sessions. `leader` is left a session because its
process is not known. Another tool that is named `grok` still matches by name: none is known on this Mac, and the path
alone would miss a Grok Build that is installed in another place.

## 2. State with no install [MAC] [BIN] [DOC]

- [DOC] `17-sessions.md`: sessions are stored in `~/.grok/sessions/<encoded-cwd>/<session-id>/`, the working directory
  URL-encoded. A name over 255 bytes gets another form. `GROK_HOME` moves `~/.grok`.
- [MAC] The owner has one session: `sessions/%2FUsers%2F<user>%2F<folder>/019f94b8-...` with `events.jsonl` (724 KB,
  8573 lines), `chat_history.jsonl`, `signals.json`, `plan_mode.json`, `rewind_points.jsonl`, `hunk_records.jsonl`,
  `resources_state.json`, `announcement_state.json`, `prompt_context.json`, `system_prompt.txt`, `plan.md`, `terminal/`,
  `recap_requests/`, `summary.json.lock`, `updates.jsonl.lock`.
- [MAC] `events.jsonl`: one compact JSON object per line, each with `ts` (ISO 8601 with milliseconds, UTC) and `type`.
  No text of the user or of the model. Types and their other keys:

  | type | keys | count |
  |---|---|---|
  | `turn_started` | `session_id` (the folder name), `turn_number`, `model_id`, `yolo_mode`, `conversation_message_count`, `session_relationship` (`primary`), `schema_version` (`1.0`) | 13 |
  | `turn_ended` | `outcome` (`completed` in all 13) | 13 |
  | `loop_started` | `loop_index` | 42 |
  | `first_token` | | 42 |
  | `phase_changed` | `phase`: `waiting_for_model`, `streaming_reasoning`, `streaming_text`, `tool_execution`, `permission_prompt` | 8141 |
  | `tool_started` | `tool_name` | 72 |
  | `permission_requested` | `tool_name` | 72 |
  | `permission_resolved` | `tool_name`, `decision` (`allow` 71, `deny` 1), `wait_ms` | 72 |
  | `tool_completed` | `tool_name`, `duration_ms`, `outcome` (`success`, `error`) | 69 |
  | `yolo_toggled` | `enabled` | 4 |
  | `mcp_*` | server names and counts | 33 |

- [MAC] Order of one turn: `turn_started`, `loop_started`, `phase_changed` (many: one per piece of the answer),
  `tool_started`, `phase_changed permission_prompt`, `permission_requested`, `permission_resolved`, `tool_completed`,
  the next loop, `turn_ended`. No line of a turn came after its `turn_ended`: 0 of 8500. The only lines outside a turn were
  `mcp_*`. A `yolo_toggled` came between a request and its answer.
- [MAC] Every tool call had a `permission_requested`, also `read_file` and `grep`, with the permission mode `auto` in
  the owner's config. All 72 got their answer after 2.4 to 12.6 seconds (median 3.0, 63 of them under 5). So a request is
  not a wait for the user by itself: Grok Build decides most of them itself, and that takes seconds. [INFERRED] the long
  ones were answered by the user. `GrokSummary.askSettle` = 15 s: a request that is open for longer is a wait.
- [BIN] The same event names are in the 0.2.111 binary, in one block: `turn_started ... phase_changed ... first_token
  loop_started tool_started tool_completed permission_requested permission_resolved wait_ms turn_ended
  cancellation_category cancellation_context interjected yolo_toggled ...`, with the outcomes `completed`, `cancelled` and
  the categories `hook_denied, permission_rejected, permission_cancelled, mid_turn_abort`. [INFERRED] a turn that the user
  stops gets a `turn_ended` with `outcome: cancelled`. [UNKNOWN] not seen: the owner's 13 turns all completed. The log was
  written in July by an older build, the names are the same in 0.2.111.
- [MAC] `active_sessions.json` was `[]` with no session, and still `[]` [TMP] with the TUI open at its sign-in screen.
  [BIN] `struct ActiveSession with 4 elements`, with the fields `pid` and `opened_at` next to it. So it lists open
  sessions with their pid and holds no state. [UNKNOWN] the names of the other two fields, so it is not read.
- [MAC] `signals.json` holds counters (`turnCount`, `cancellationCount`, `toolCallCount`, ...) and no state.
  `plan_mode.json` has `awaiting_plan_approval`. `logs/unified.jsonl` is a debug log.
- The log carries no pid. `EvidenceCollector.fillGrok` takes the logs of the folder that is named after the process's
  working directory and that were written since the process started. With two Grok Build sessions in one directory, and
  with no log yet (no prompt), the session is judged as before: by the signs of activity, and by the hooks.

What the reader gives: working from `turn_started` to `turn_ended` with no time limit (a quiet tool call writes
nothing), waiting for a request that is open for 15 seconds, idle with the time of `turn_ended`.

## 3. Hooks [DOC] [TMP]

All of this section is `10-hooks.md` unless marked.

- Locations, all merged: `~/.grok/hooks/*.json` (always trusted), `~/.claude/settings.json` and `settings.local.json`
  (Claude Code compatibility, on by default), `~/.cursor/hooks.json` (Cursor compatibility, on by default),
  `<project>/.grok/hooks/*.json` and the project's Claude and Cursor files (need `/hooks-trust`), and plugins.
  `[compat.claude] hooks = false` in `config.toml` turns the Claude scan off (`05-configuration.md`). Hooks are not
  set in `config.toml`.
- Form of a file: `{"hooks": {"<Event>": [{"matcher": "...", "hooks": [{"type": "command", "command": "...",
  "timeout": 5}]}]}}`, the form of Claude Code. `type` is `command` or `http`. `command` is a path relative to the file
  or a shell line, and `$VAR` in it is expanded when the file is loaded. `timeout` is in seconds: default 5, and 600 for
  `Stop` and `SubagentStop`.
- Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse` (can deny), `PostToolUse`, `PostToolUseFailure`,
  `PermissionDenied`, `Stop` (can block the stop), `StopFailure`, `Notification`, `SubagentStart`, `SubagentStop` (can
  block), `PreCompact`, `PostCompact`, `SessionEnd`. "every other event is passive", and for those "stdout is ignored".
  Cursor's camelCase names are accepted and mapped. A matcher on `Stop` or `UserPromptSubmit` is ignored with a warning.
- Input: JSON on stdin with camelCase keys: `hookEventName` (snake_case value, as `pre_tool_use`), `sessionId`, `cwd`,
  `workspaceRoot`, `timestamp`, `permissionMode`, and per event `toolName`, `toolInput`, `toolUseId`, `toolResult`,
  `reason`, `stopHookActive`, `lastAssistantMessage`, `backgroundTasks`, `error`. [BIN] also `transcriptPath`,
  `notificationType`, `subagentId`, `subagentType`. Environment: `GROK_HOOK_EVENT`, `GROK_HOOK_NAME`, `GROK_SESSION_ID`,
  `GROK_WORKSPACE_ROOT`, `CLAUDE_PROJECT_DIR`.
- Answers: `PreToolUse` reads `{"decision": "allow"|"deny"}` and exit code 2. `Stop` reads `{"decision": "block"}`,
  `{"continue": false}` and exit code 2, and "Allow the stop: exit 0 with no output". "All hook failures (timeouts,
  crashes, malformed output ...) are fail-open".
- `Stop` fires only for "a genuine completion": "Interrupted (Esc / Ctrl+C), refused, and max-turns turns skip Stop hooks
  entirely, and API-error turns fire `StopFailure` instead." One more `Stop` fires when the session ends (`reason:
  "channel_closed"` or `"shutdown"`). Inside a subagent the event is `SubagentStop`.
- "Keep hooks fast -- long-running hooks block the UI." [UNKNOWN] whether two hooks of one event run at the same time.
  Our hook command takes its own start time as the time of the event and writes under a lock, as for the other agents.
- A changed file is loaded at the next start, or with `r` in the Hooks tab (`/hooks`).
- [UNKNOWN] the values of `notificationType`. [BIN] `permission_prompt` and `idle_prompt` are in the binary next to
  "Tool permission requested" and "Turn complete". Not registered: the event log says the wait.
- [MAC] The owner's `~/.grok/hooks/` holds files of three other tools: `cmux-session.json` (6 events), `herdr.json` with
  `herdr-agent-state.sh` (1 event), `vibe-island.json` (11 events). All in the form above, one group per event.

What we register (`HookEvents.rules["grok"]`): `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure` (working), `Stop`,
`StopFailure` (idle), `SessionEnd` (end). Every command is `[ -x <hook> ] && <hook> grok <Event> v=1 || true`: it prints
nothing and exits 0, and that is "allow the stop" for `Stop`. `PreToolUse` is never registered. The timeout is 5 seconds
for each, also for `Stop`.

[TMP] Checked with the real binary: `grok inspect --json` in a home folder of its own, with the file our installer wrote,
two backups of it (`agent-caffeine.json.agent-caffeine-backup-<time>`), a file of another tool and a
`~/.claude/settings.json` with our Claude Code entries. It listed each of our six entries once with `source.type: "user"`,
the other tool's entry, and the two Claude Code entries. So the backups are not loaded, and Grok Build does run the Claude
Code hooks of the user.

The Claude Code hook under Grok Build: the command is `CaffeinagentHook claude <Event>`. `HookCommand.agentProcess` takes
the nearest agent above the hook command, finds Grok Build, and Grok Build is not in the definitions of `claude`. Nothing
is written (`GrokHookTests.testTheHookLandsOnGrokBuildAndAReplayedClaudeHookOnNothing`). The same holds for our Cursor
entries. The `PreToolUse` of the Claude entry prints nothing and exits 0, which allows the tool.

## 4. Approval model [DOC]

- `22-permissions-and-safety.md`: the modes are `default` (asks), `acceptEdits`, `auto`, `dontAsk`, `plan`,
  `bypassPermissions` (always-approve, `--always-approve`). In `default` a command that is not read-only prompts. A
  headless run (`-p`) cancels a call that would prompt.
- The wait is in the event log (section 2). The terminal notifications of Grok Build know `approval_required` and
  `turn_complete` (`05-configuration.md`), which are not hook events.

## 5. What was not possible

[TMP] Grok Build does not start a session without an account. With an empty home folder the TUI showed its sign-in step
and started its sign-in by itself (`auth: inline auth flow` in its log). The sign-in completed 12 seconds later with no
action of ours, and Grok Build wrote a new `auth.json` into the home folder in `/tmp`. [INFERRED] it went through the
browser of the owner, which was signed in to grok.com. The process was stopped with
SIGINT 24 seconds later. No session folder was made, no hook ran, no prompt was sent. The `auth.json` in `/tmp` was not
read and was deleted. The owner can end that sign-in in his xAI account.

So nothing of a live turn is measured for 0.2.111: no hook event was seen to arrive, and `events.jsonl` was read from a
session of July. To measure:

1. A prompt with a quiet command (`sleep 120`): `turn_started` is written at the prompt, the log is silent during the
   command, `turn_ended` comes at the end. With the hooks on: a state file `grok-<pid>.json` in the hooks folder of Agent
   Caffeine after the prompt.
2. An approval in the mode `default`: `permission_requested` stays open while the dialog shows.
3. Esc in the middle of a turn: a `turn_ended` with `outcome: cancelled`. If none is written, the turn reads as working
   until Grok Build quits, and the reader needs the last write time as a second sign.
4. Whether tool commands are children of the `grok` process, and what holds the power assertion.
5. Two sessions in one folder, `--worktree` and `--cwd`: whether the working directory of the process is the folder the
   session is stored under.
