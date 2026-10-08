# 08 - Cursor desktop: how to detect working, waiting, idle

Date: 2026-10-07. Mac of the owner. Cursor 3.22.12 (VS Code 1.128.0, commit 3a929743, built 2026-09-26),
bundle id `com.todesktop.230313mzl4w4u92`, `/Applications/Cursor.app`. Read-only work. No app was started, stopped or signalled.
Companion file from the coordinator: `08b-cursor-live-run.md` (2 s sampler of one agent session). This file builds on it.

Marks: [DOC] official docs. [OSS] open source read. [BUNDLE] read in the installed Cursor JavaScript. [MAC] measured on this Mac.
[INFERRED] not proven. [UNKNOWN] must be measured.

## 0. The five facts that decide the design

1. [BUNDLE][MAC] **Cursor takes its own sleep assertion while a local agent turn runs, and drops it when the turn waits for
   your approval.** This corrects item 6 of `08b` ("Cursor held no power assertion"): the assertion type is
   `NoIdleSleepAssertion` with the name `"Electron"`, owned by the MAIN process, so a search for "Cursor" or for
   `PreventUserIdleSystemSleep` in the name column misses it.
   - Seen: `pid 53634(Cursor): [..] 00:00:49 NoIdleSleepAssertion named: "Electron"` at 10:18:06 during the run. None at 10:14:22 (idle) and 10:19:05 (done).
   - Code (`composerWakelockManager.js` in `out/vs/workbench/workbench.desktop.main.js`): on each submit Cursor makes a manager,
     unless the conversation was made from a cloud agent (`createdFromBackgroundAgent?.bcId`). The manager calls
     `powerMainService.startWakelock("agent-loop")` (Electron `powerSaveBlocker.start("prevent-app-suspension")`),
     unless `hasBlockingPendingActions` is already true. It watches `hasBlockingPendingActions`: true -> release with reason
     `"user-approval-requested"`; false again -> acquire with reason `"agent-loop-resumed"`. At the end: release with reason `"generation-ended"`.
     It is the only caller of `startWakelock` in the workbench. No setting or feature gate guards it.
   - Logs, with times that match the run:
     `logs/<stamp>/main.log`: `[PowerMainService] Started wakelock id=2 owner=window:1 reason="agent-loop" activeCount=1`, `... Stopping wakelock id=2 ... heldForMs=76307`.
     `logs/<stamp>/window1_wb0/renderer.log`: `[ComposerWakelockManager] Acquired wakelock id=2 reason="agent-loop" composerId=<uuid>`, `Released wakelock id=2 reason="generation-ended" composerId=<uuid>`.
   - Meaning for us: Cursor already stops idle sleep for a local turn. It does not stop lid-closed sleep. Our engine already has
     the evidence field `ownsSleepAssertion` ("pwr") and counts it as a strong sign.
2. [MAC][BUNDLE] **Transcript JSONL with turn markers** at `~/.cursor/projects/<slug>/agent-transcripts/<conversation-id>/<conversation-id>.jsonl`.
   Last line `{"type":"turn_ended","status":"success"}` = idle. Other statuses in the writer code: `"error"` (with an `error` text) and
   `"aborted"` (the `error` text is optional). A `user` or `assistant` line last = a turn in progress or a turn that waits for approval.
   Lines carry no time. The file is not written during a long command (08b), so use the marker, not the write time.
3. [MAC] **Agent shell commands are children of the extension host**, not of the pty host:
   `Cursor` (main) -> `Cursor Helper (Plugin): extension-host Agents Window [1-1]` -> `/bin/zsh -c builtin export PATH=...; snap=$(command cat <&3); ...` -> `sleep 60`.
4. [DOC][MAC] **Hooks run in the editor's agent**, from `~/.cursor/hooks.json`. No hook event exists for an approval wait. Cursor also runs the hooks of
   `~/.claude/settings.json` (setting on by default), so Agent Caffeine's Claude hook already ran inside Cursor today (29 times) and was ignored by our hook command, as designed.
5. [DOC][BUNDLE] **Cloud agents**: user-level hooks do not run there, Cursor takes no wake lock for them, and their commands are not local processes.

## 1. Process model [MAC]

| Process (title as `ps` shows it) | Executable (`proc_pidpath`) | Parent | Note |
|---|---|---|---|
| `/Applications/Cursor.app/Contents/MacOS/Cursor` | same | launchd | Main. Owns the sleep assertion. One per app. |
| `Cursor Helper (Plugin): extension-host Agents Window [1-1]` | `.../Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)` | main | Extension host. Holds `AgentStores/*/.sync/index.sqlite*` and the `exthost` logs. Runs `anysphere.cursor-agent-exec`, `cursor-agent-host`, `cursor-retrieval`, `cursor-always-local`, `cursor-mcp`, `cursor-socket`. Parent of agent shell commands. |
| `Cursor Helper (Plugin) ... extensions/cursor-always-local/dist/gitWorker.js` | same Plugin helper | extension host | Always there. |
| `Cursor Helper: shared-process`, `: fileWatcher [1:empty-window]`, `: mcp-process`, `: conversation-search`, `: terminal pty-host` | `.../Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper` | main | `terminal pty-host` was absent at idle (10:14, 10:15) and present at 10:18 during the run. `conversation-search` holds `state.vscdb` (read) and `conversation-search.db`. |
| `Cursor Helper (Renderer) --type=renderer`, `Cursor Helper --type=gpu-process`, network and audio utilities | Renderer / plain helper | main | UI. |
| `chrome_crashpad_handler`, `ShipIt` | Electron and Squirrel frameworks | launchd | Not in the main subtree. |

- The process title is rewritten, so `argv[0]` is the title. The executable path is not rewritten.
- Title of the extension host in a classic editor window: [UNKNOWN] here. Forum reports name `extension-host (agent-exec)`, `extension-host (retrieval-always-local)` and `extension-host (user)` for Cursor 2.x editor windows (forum.cursor.com/t/156061, Cursor 2.6.21). So an editor window can have more than one extension host.
- No process exists only for the length of an agent turn, apart from the agent's own shell commands. [MAC]
- Bundled binaries (names only): `Contents/Resources/app/bin/{cursor,code,cursor-tunnel}`, `resources/helpers/{node,cursorsandbox,crepectl,cursor-update-supervisor}`. No `cursor-agent` binary in the app. Extensions: `cursor-agent-exec`, `cursor-agent-host` ("Hosts Cursor agent orchestration in the AgentExec extension host"), `cursor-agent-worker` ("Install and run Cursor agent worker from extension startup"), `cursor-local-agent-runtime`, `cursor-shadow-workspace`, `cursor-retrieval`, `cursor-always-local`, `cursor-computer-use`, `cursor-browser-automation`, `cursor-mcp`, `cursor-socket`, `cursor-checkout`, `cursor-worktree-textmate`.
- `product.json`: `dataFolderName=.cursor`, `applicationName=cursor`, `urlProtocol=cursor`, `serverDataFolderName=.cursor-server`.
- Environment that the agent-exec extension sets for its shells (names found in its code): `CURSOR_AGENT`, `CURSOR_CONVERSATION_ID`, `CURSOR_REQUEST_ID`, `CURSOR_SANDBOX`. [BUNDLE] The docs name `CURSOR_AGENT` too (cursor.com/docs/agent/tools/terminal.md).
- `resources/tray-status/{running,attention,unread}` icons exist: Cursor has its own menu bar status. No way to read it from outside is known.

### CPU [MAC]
CPU time per process. Idle = 68 s (10:14:22 to 10:15:30). Run = 156 s (10:15:30 to 10:18:06, most of it an agent turn).

| Process | Idle | Run |
|---|---|---|
| main | 0.44 s (0.6 %) | 2.71 s (1.7 %) |
| renderer | 1.63 s (2.4 %) | 27.2 s (17 %) |
| GPU helper | 0.13 s (0.2 %) | 29.1 s (19 %) |
| extension host | 0.89 s (1.3 %) | 4.44 s (2.8 %) |
| all others | about 0 | about 0 |

The extension host says nothing (same as 08b). The renderer and the GPU helper are busy when text streams, and also when the user scrolls or types. CPU is weak evidence only.

## 2. On-disk state [MAC]

`~/Library/Application Support/Cursor/`
- `User/globalStorage/state.vscdb` (+ `-wal`, `-shm`). Tables: `ItemTable`, `cursorDiskKV`, **`composerHeaders`** (columns `composerId, workspaceId, createdAt, lastUpdatedAt, isArchived, isSubagent, recency, checkpointAt, subagentTypeName, value`).
  - `cursorDiskKV` keys: `composerData:<id>`, later also `bubbleId:<composerId>:<bubbleId>`, `agentKv:*`, `checkpointId:*` [OSS].
  - `composerHeaders.value` JSON keys include `hasBlockingPendingActions`, `hasPendingPlan`, `agentLocation`, `agentLocationHistory`, `unifiedMode`, `isWorktree`, `lastUpdatedAt`, `hasUnreadMessages`.
  - `composerData` JSON keys include `status`, `generatingBubbleIds`, `chatGenerationUUID`, `latestChatGenerationUUID`, `unfinishedRunAt`, `isAgentic`, `unifiedMode`, `fullConversationHeadersOnly`, `subagentComposerIds`, `stopHookLoopCount`.
  - **`status` is stale**: after two finished turns the checkpointed row still said `aborted`, with an empty `generatingBubbleIds`. The open source monitor LuckyBit541/agent-monitor (commit a6ecda2, 2026-09-30, `cursor_float.py`) found the same on Windows: during a generation `status` and `generatingBubbleIds` do not change; only the content of `composerData` changes (bubble count, last bubble id); the last bubble's `toolFormerData.status == "loading"` marks a running tool; `hasBlockingPendingActions` in the header marks an approval wait. [OSS]
  - The data lives in the WAL for a long time (WAL 4.8 to 5.7 MB, main file checkpointed at 10:15:47). `immutable=1` reads only the checkpointed part. A live reader needs `mode=ro` without `immutable`, which takes a shared read lock on Cursor's database.
  - The WAL's mtime also moved at idle (10:14:22 -> 10:15:20, same size). Not a usable activity signal.
  - `ItemTable` has keys such as `cloudAgentRepository.agents.<auth id>` and `cloudAgentRepository.serverPinnedBcIds.<auth id>`: the cloud agent list is separate from local composers.
- `User/workspaceStorage/<id or empty-window>/state.vscdb`: one per workspace.
- `AgentStores/cursor_agent_stores/<conversation-id or u<number>>/.sync/{index.sqlite, -wal, sync.lock, mount.json}`: written every few seconds at idle. Noise. Never use.
- `logs/<YYYYMMDDTHHMMSS>/` (one folder per app start): `main.log`, `window<N>_wb0/renderer.log`, `window<N>_wb0/exthost/anysphere.cursor-agent-exec/Cursor Agent Exec.<stamp>.log` (written only during agent work, 08b), `window<N>_wb0/output_<stamp>/cursor.hooks.workspaceId-<workspace>.log`.
  - **Privacy**: the hooks log holds the full hook input and output (prompt text, file text, e-mail). Do not read it in the app. `main.log` and the wake lock lines of `renderer.log` hold only ids and reasons.
  - Idle noise in logs: `Cursor Structured Logs`, `renderer.log`, `mcpprocess.log`, `Mcp FileSystem Writer`. No idle writes: the hooks log, `Cursor Agent Exec`, transcripts.
- `3.22-main.sock`: the main process socket. Not examined.

`~/.cursor/`
- `projects/<slug>/agent-transcripts/<conversation-id>/<conversation-id>.jsonl`; subagent transcripts in `<conversation-id>/subagents/` [OSS]. Older Cursor wrote `agent-transcripts/<id>.jsonl` or `.txt` directly [OSS: vibe-replay.com/blog/cursor-local-storage]. Glob both depths.
  - Writer: `cursor-agent-host` (`TranscriptStore`). It can append, and it can rewrite the whole file as a fallback. A first line `{"type":"metadata",...}` can exist. So: read the last non-empty line again after each change of size or mtime; do not keep a byte offset as the only truth. [BUNDLE]
  - Line shapes: `{"role":"user"|"assistant","message":{"content":[{"type":"text"|"tool_use","name":...,"input":...}]}}` and `{"type":"turn_ended","status":"success"|"error"|"aborted","error"?}`. No tool results, no times, no model. [MAC][BUNDLE]
  - Cursor deletes old agent data (30 days in the code; marker file `projects/.agent-data-cleanup-<date>`). [BUNDLE]
  - `transcript_path` in the hook input is "null if transcripts disabled" [DOC]: a user can have no transcripts. Which setting: [UNKNOWN].
- **Slug rule** [BUNDLE]: `s.replace(/[^a-zA-Z0-9]/g,"-").replace(/-+/g,"-").replace(/^-+|-+$/g,"")`, in `workspace-paths.ts`, next to the constants `.cursor/projects` and `agent-transcripts`. So `/Users/me/code/my.app` should give `Users-me-code-my-app`. A window with no folder gives `empty-window` [MAC]. That the input is the workspace folder path is [INFERRED]: check with a real folder. A second function (`encodeURIComponent`, `%` -> `_`, cut at 200) exists for another id.
- `projects/<slug>/{mcps,canvases,terminals,agent-notes,agent-tools}`, `ai-tracking/ai-code-tracking.db` (written when the agent edits files: 10:17:02), `agents/` (user subagent definitions), `subagents/` (output of background subagents [DOC]), `worktrees/<repo>/<name>` (worktree agents [DOC]), `plugins/`, `skills-cursor/`, `hooks.json`, `mcp.json`, `argv.json`, `cli-config.json` (CLI [DOC]), `chats/<hash>/<id>/store.db` (CLI chats [OSS]).

## 3. Hooks [DOC: cursor.com/docs/hooks.md and cursor.com/docs/reference/third-party-hooks.md, fetched 2026-10-07]

Format:
```json
{ "version": 1, "hooks": { "stop": [ { "command": "…", "timeout": 5 } ] } }
```
- `version`: "Config schema version. Must be a positive integer (use `1`)."
- Per entry: `command` (required), `type` (`"command"` default, or `"prompt"`), `timeout` (seconds), `loop_limit` (stop and subagentStop), `failClosed` (default false), `matcher` (regex).
- Files and priority: Enterprise `/Library/Application Support/Cursor/hooks.json` -> Team (dashboard) -> Project `<root>/.cursor/hooks.json` (trusted workspaces only) -> User `~/.cursor/hooks.json`. "All matching hooks from every source run". User hooks run with the working directory `~/.cursor/`.
- "Cursor watches hooks config files and reloads them automatically." No restart.
- Agent events ("apply to Cmd+K and Agent Chat operations"): `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`, `subagentStop`, `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`, `afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`, `preCompact`, `stop`, `afterAgentResponse`, `afterAgentThought`. Tab events: `beforeTabFileRead`, `afterTabFileEdit`. App event: `workspaceOpen` ("Runs in the Cursor desktop app and CLI").
- Input that every agent hook gets: `conversation_id` ("Stable ID of the conversation across many turns"), `generation_id` ("changes with every user message"), `model`, `model_id`, `model_params`, `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email`, `transcript_path` ("null if transcripts disabled").
- [MAC] Measured 2026-10-07: `conversation_id` is the name of the transcript folder (`agent-transcripts/<conversation-id>/`). The keys of both sessions in our hook state file were the hashes of the two transcript folder names.
- [MAC] Measured 2026-10-07, at the usage limit: a prompt that fails at once fires `beforeSubmitPrompt` and no `stop`. The transcript gets one line, `{"type":"turn_ended","status":"error","error":...}`, 0.7 to 0.8 s after the hook. No wake lock was held 30 s later.
- Per event:
  - `beforeSubmitPrompt`: input `prompt`, `attachments`. Output `{"continue": true|false, "user_message"}`. "Called right after user hits send but before backend request."
  - `stop`: input `status: "completed" | "aborted" | "error"`, `loop_count`. Output `followup_message` (optional; when present Cursor submits it as the next user message). "Called when the agent loop ends."
  - `beforeShellExecution`: input `command`, `cwd`, `sandbox`. Output `permission: "allow" | "deny" | "ask"`, `user_message`, `agent_message`.
  - `afterShellExecution`: input `command`, `output`, `duration` ("excludes approval wait time"), `sandbox`. No output.
  - `afterAgentResponse`: input `text`. No output. `afterAgentThought`: input `text`, `duration_ms`. "No output fields currently supported".
  - `preToolUse`: input `tool_name`, `tool_input`, `tool_use_id`, `cwd`, `agent_message`. Output `permission: allow|deny`, `updated_input`. `postToolUse`: adds `tool_output`, `duration`; output can inject context. `postToolUseFailure`: `failure_type: "timeout" | "error" | "permission_denied"`, `is_interrupt`.
  - `sessionStart`: `session_id` ("same as `conversation_id`"), `is_background_agent`, `composer_mode`. Fire and forget. `sessionEnd`: `session_id`, `reason: "completed" | "aborted" | "error" | "window_close" | "user_close"`, `duration_ms`, `is_background_agent`, `final_status`. "The response is logged but not used."
  - `subagentStart` (permission), `subagentStop` (`status`, `agent_transcript_path`, can send a follow-up), `preCompact` (observe only).
- Blocking rules: "Exit code `0` - Hook succeeded, use the JSON output. For permission hooks (`beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `beforeTabFileRead`, `subagentStart`, `preToolUse`), invalid JSON or a response that doesn't match the hook's schema blocks the action." "Exit code `2` - Block the action". "Other exit codes - Hook failed, action proceeds (fail-open by default)". `failClosed: true` makes "crash, timeout, non-zero exit code, no output" block.
- **Passive set** (no output is read, or the output is optional): `afterShellExecution`, `afterMCPExecution`, `afterFileEdit`, `afterAgentResponse`, `afterAgentThought`, `postToolUse`, `postToolUseFailure`, `stop`, `sessionStart`, `sessionEnd`, `preCompact`, and `beforeSubmitPrompt` (not in the list of permission hooks).
- **Not passive by the docs' wording**: the six permission hooks. Measured today [MAC]: Claude-format hooks that print nothing ran on `preToolUse` 13 times ("Hook N produced no output", "All hooks for step preToolUse completed but none returned a valid response") and the tools still ran. So an empty answer did not block in 3.22.12. The docs still allow a block, so we should not depend on this.
- **Approval wait: no event.** [DOC] The third-party table says `Notification` and `PermissionRequest` are "No". [MAC] The hooks log says: `[Claude] Claude Code event "PermissionRequest" is not supported in Cursor and will be ignored`, the same for `Notification`, and `Unknown Claude Code event` for `StopFailure`, `SubagentStart`, `PostCompact`, `TeammateIdle`.
- Editor and CLI: the editor is proven [MAC]. CLI: superset's hook template comment says "the cursor-agent CLI stamps CURSOR_AGENT/CURSOR_CLI into its env; anything else is the IDE Composer" [OSS, superset-sh/superset `packages/agent-setup/templates/cursor-hook.template.sh`], and cmux installs `~/.cursor/hooks.json` for the binary `cursor-agent` [OSS]. The docs page has no CLI event table. Which events fire in the CLI: [UNKNOWN].
- Cloud [DOC]: "User-level hooks (`~/.cursor/hooks.json`) are not available in cloud agents." Project hooks do run in the cloud VM, not on the Mac. `sessionStart`/`sessionEnd` do not run for cloud agents.
- Environment for a hook [DOC]: `CURSOR_PROJECT_DIR`, `CURSOR_VERSION`, `CURSOR_USER_EMAIL`, `CURSOR_TRANSCRIPT_PATH`, `CURSOR_CODE_REMOTE`, `CLAUDE_PROJECT_DIR`.
- Third-party import [DOC]: Claude hooks load when "Include Third-Party Plugins, Skills, and Other Configs" is on ("on by default"), from `.claude/settings.local.json`, `.claude/settings.json`, `~/.claude/settings.json`. Mapping: `PreToolUse`->`preToolUse`, `PostToolUse`->`postToolUse`, `UserPromptSubmit`->`beforeSubmitPrompt`, `Stop`->`stop`, `SubagentStop`->`subagentStop`, `SessionStart`, `SessionEnd`, `PreCompact`.
- This Mac's `~/.cursor/hooks.json` (structure only): `{"version":1,"hooks":{<12 events>: [{"command": "<Vibe Island bridge> --source cursor"}]}}`, one entry per event, key `command` only.

### What other tools register [OSS]
| Tool | Events | Output |
|---|---|---|
| jmslau/claude-caffeine (c124886, `CursorHookInstaller.swift`) | working: `beforeSubmitPrompt, preToolUse, postToolUse, beforeShellExecution, afterAgentThought, subagentStart`; idle: `stop, sessionEnd` | prints nothing; key `conversation_id || session_id`; file per session with `pid: process.ppid` |
| manaflow-ai/cmux (`CMUXCLI+AgentHookCatalog.swift`) | `beforeSubmitPrompt, stop, afterAgentResponse, beforeShellExecution, afterShellExecution, postToolUseFailure` (matcher `Shell`) | format "flat" |
| asheshgoplani/agent-deck (`cursor_hooks.go`) | `sessionStart, sessionEnd, beforeSubmitPrompt, preToolUse, postToolUse, stop` | |
| superset | prints `{"continue":true}` for its permission event "so cursor-agent isn't left blocked" | |
| Vibe Island (this Mac) | the 12 events above | returns a valid response |

### The entry Agent Caffeine would add
New hook agent id `cursor`, config `~/.cursor/hooks.json`, a new installer format "flat" (`hooks.<event>` is an array of `{command, timeout}` objects, with no `matcher` wrapper and no inner `hooks` array; top-level `"version": 1` must exist, add it only when missing).

```json
{ "command": "[ -x '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' ] && '/Applications/agent caffeine.app/Contents/MacOS/CaffeinagentHook' cursor stop v=1 || true", "timeout": 5 }
```
| Event | Action |
|---|---|
| `beforeSubmitPrompt` | working |
| `afterAgentThought`, `afterAgentResponse`, `postToolUse`, `postToolUseFailure`, `afterShellExecution`, `afterFileEdit`, `afterMCPExecution` | working |
| `stop` | idle |
| `sessionEnd` | end |

- Leave out the six permission events and `subagentStop` (a subagent stop is not the end of the turn; Cursor has no `agent_id` field for our filter).
- `HookInput.sessionKeys` must also accept `conversation_id` (today: `session_id`, `sessionID`, `sessionId`).
- The hook command finds its agent by walking up the process tree. With the matcher of section A the chain is hook -> (shell) -> extension host (helper) -> `Cursor` main (engine). Which process starts the hook: [UNKNOWN], measure.
- Remove: delete each array element whose `command` contains `/Contents/MacOS/CaffeinagentHook`; delete an event key whose array is then empty; leave `version` and all other entries. The same marker rule as today.
- A hook gives no "waiting" state. It gives exact turn start and end, which the transcript also gives. So hooks are optional for Cursor.

## 4. Logs
- Path: `~/Library/Application Support/Cursor/logs/<start stamp>/…`. A new folder per app start; `window<N>_wb0` per window. Stable in shape, not in name. [MAC]
- Lines for turn start, approval wait and end: the wake lock lines of section 0. [MAC] for start and end, [BUNDLE] for `user-approval-requested` and `agent-loop-resumed`.
- Log wording is internal and can change in any release. Use it for measurement and as a last resort.

## 5. Power
Section 0. [DOC] No setting "prevent sleep while agent runs" is in the docs. [BUNDLE] Other power settings: `glassRemoteControlKeepAwakeWhilePluggedIn` (default false; Remote Control feature) and `remote.tunnels.access.preventSleep` (VS Code tunnels). Either could make Cursor hold an assertion with no agent turn: then "assertion = working" is wrong. Whether they use the same `"Electron"` assertion: [UNKNOWN].

## 6. Cloud agents
- [DOC] cursor.com/docs/cloud-agent.md: cloud agents "run in isolated VMs in the cloud"; "they do not require your local machine to be connected". "Cloud Agents were formerly called Background Agents." Started from the desktop with "Cloud" in the dropdown, or `/in-cloud` (cloud subagent), or `/autopilot`.
- [BUNDLE] No wake lock for a conversation with `createdFromBackgroundAgent.bcId`. [DOC] No user hooks. [INFERRED] No local child commands.
- Does a cloud run write a local transcript, and does a cloud SUBAGENT of a local turn keep the local turn "in progress"? [UNKNOWN]. Rule that is safe either way: a transcript "in progress" counts as working only together with the assertion, a child command, or a recent write.
- Exception [DOC] cursor.com/docs/cloud-agent/self-hosted/my-machines.md: "My Machines" runs cloud agent tool calls on the user's Mac through `agent worker start` (the CLI). Then the Mac must stay awake. The process is the CLI `agent` (older name `cursor-agent`), not the app. The catalogue matches `cursor-agent` only. The name `agent` is too general to match by name alone: open point.

## 7. Relatives (cheap checks only)
- **Claude Code extension in VS Code** [MAC]: `~/.vscode/extensions/anthropic.claude-code-2.1.270-darwin-arm64/resources/native-binary/claude` is a real `claude` binary. Its path is not inside an `.app` and its file name is `claude`, so the present `.name("claude")` matcher takes it. A live run in VS Code was not observed today.
- **VS Code Copilot agent mode** [DOC] code.visualstudio.com/docs/copilot/customization/hooks: hooks are in Preview. Files: `.github/hooks/*.json`, `~/.copilot/hooks/*.json`, and Claude settings when `chat.useClaudeHooks` is on. Events: `SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PreCompact, SubagentStart, SubagentStop, Stop`. No approval-wait event. Process model is the same Electron shape (`Code Helper (Plugin)` extension host). Not measured.
- **Windsurf** (docs now at docs.devin.ai/desktop/cascade/hooks; "Devin Desktop IDE") [DOC]: `~/.codeium/windsurf/hooks.json`, workspace `.devin/hooks.json`. Events: `pre_user_prompt`, `post_cascade_response`, `post_cascade_response_with_transcript`, `pre_run_command`, `post_run_command`, `pre_write_code`, `post_write_code`, `pre_read_code`, `post_read_code`, `pre_mcp_tool_use`, `post_mcp_tool_use`, `post_setup_worktree`. Input: `agent_action_name`, `trajectory_id`, `execution_id`, `timestamp`. `pre_*` can block with exit code 2; `post_*` observe only. No approval-wait event. Not installed here; engine process not measured.

## A. Detection plan for `cursor-desktop`

| Element | Rule | Mark |
|---|---|---|
| Engine | `AgentMatcher(.appBundle(bundle: "Cursor.app", relativePath: "Contents/MacOS/Cursor"))`, role engine. One per running app. | [MAC] |
| Helpers | Exclusions with role `.helper` for `Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper`, `…/Cursor Helper (Plugin).app/…/Cursor Helper (Plugin)`, `…/Cursor Helper (Renderer).app/…`, `…/Cursor Helper (GPU).app/…`. They stay in the engine's subtree (CPU, assertion) and are not counted as child commands. | [MAC] for paths, [INFERRED] from our code for the effect |
| Why the main process and not the extension host | The assertion is owned by the main pid. There can be several extension hosts. Commands are grandchildren of main through a helper, which our child rule accepts (parent is a matched pid). | [MAC][BUNDLE] |
| Level | `.state` when a transcript is readable, else `.activity`. | |
| Open with a live session | A transcript under `~/.cursor/projects/*/agent-transcripts/` written within `liveSessionAge` (3600 s), or any working sign. | [MAC] |
| Working 1 | Any transcript (not in `subagents/`) whose last line is not `turn_ended`, AND one of: the engine owns a sleep assertion; a child command exists; the file was written in the last N minutes. | [MAC] marker, [INFERRED] the AND |
| Working 2 | The engine owns `NoIdleSleepAssertion "Electron"` (already `ownsSleepAssertion`). Works with transcripts disabled and with no hooks. | [MAC][BUNDLE] |
| Working 3 | Hook state (optional, section 3). | [DOC][MAC] |
| Working 4 | Busy child command below a helper (zsh -> command). | [MAC] |
| Weak | Subtree CPU (renderer and GPU). Cap it as weak evidence. | [MAC] |
| Waiting for you | Last transcript line is not `turn_ended` AND the engine owns no assertion AND no child command, for more than a few seconds. Cursor drops its wake lock exactly at `hasBlockingPendingActions`. | [BUNDLE], not yet seen live |
| Idle | Last line `turn_ended` (any status), no assertion. | [MAC] |
| Cloud | Not held: no assertion, no user hooks, no local commands. | [BUNDLE][DOC] |
| Cannot see | Which of several windows waits (transcripts say which conversation, not which window); a wait with transcripts disabled (then: assertion dropped = unknown, treat as idle); cloud subagent of a local turn; My Machines worker. | |
| Never use | `AgentStores` writes, `state.vscdb-wal` mtime, `composerData.status`, extension host CPU, the hooks log. | [MAC][OSS] |

Order of work: matcher and helpers first (this alone gives "open", the assertion sign and child commands with today's verdict code); then a `CursorTranscriptReader` (tail the last line, like the Codex rollout reader); then the waiting rule after the measurement; hooks last and optional.

## B. Measurement still needed (owner, about 10 minutes)
Tool: `cursor-watch.sh` in this folder. It is read-only. It prints once per second: the Cursor assertion, the commands below each extension host, the last line TYPE of each recent transcript, and the last two wake lock log lines. It prints no chat text.

The built-in recorder (`"/Applications/agent caffeine.app/Contents/MacOS/caffeinagent" --lab-record cursor`) is safe next to the running app: `LabCommand` runs before the app starts, is headless, takes no assertion, checks no license, and only writes `~/Library/Application Support/com.caffeinagent.app/lab/`. The shipped 0.2.3 binary has the lab arguments. But 0.2.3 has no Cursor matcher, so it records "no agents" for Cursor. Use it after a build with the matcher exists.

Steps are in the final message of this research and repeated here:
1. Terminal: `"${TMPDIR%/}/agent-caffeine-research/cursor-watch.sh" 900 | tee ~/Desktop/cursor-watch.txt`
2. Approval wait: Cursor Settings > Agents > Approvals & Execution: choose "Allowlist" for this test. Ask the agent: "run `sleep 45` in the shell". Do not approve for 30 s. Then approve. Wait until done.
3. Abort: ask "run `sleep 120`". After 20 s press Stop.
4. Real folder: open a project folder in the Agents Window, send one short prompt.
5. Two at once: start a long prompt in two conversations at the same time.
6. Classic editor: Cmd+Shift+P > "Open IDE", send one prompt in its agent panel.
7. Cloud: send one small task with "Cloud" selected (optional).
8. Stop the script with Ctrl-C. Set the run mode back. Send `~/Desktop/cursor-watch.txt` and the output of `ls ~/.cursor/projects`.

What each step answers: 2 = does the assertion drop and does the log say `user-approval-requested`, what the last transcript line is during the wait; 3 = `turn_ended:aborted` or no marker at all; 4 = the slug rule; 5 = one assertion for two turns, two transcripts; 6 = extension host titles and the transcript path of the editor; 7 = local transcript and assertion for a cloud run.

## Sources
- https://cursor.com/docs/hooks.md , https://cursor.com/docs/reference/third-party-hooks.md , https://cursor.com/docs/agent/tools/terminal.md , https://cursor.com/docs/agent/security/run-modes.md , https://cursor.com/docs/agent/agents-window.md , https://cursor.com/docs/cloud-agent.md , https://cursor.com/docs/cloud-agent/self-hosted/my-machines.md , https://cursor.com/docs/subagents.md , https://cursor.com/docs/configuration/worktrees.md , https://cursor.com/docs/cli/reference/configuration.md , https://cursor.com/llms.txt
- https://github.com/LuckyBit541/agent-monitor (cursor_float.py) , https://github.com/jmslau/claude-caffeine (CursorHookInstaller.swift, PR #3) , https://github.com/manaflow-ai/cmux (CLI/CMUXCLI+AgentHookCatalog.swift) , https://github.com/superset-sh/superset (cursor-hook.template.sh) , https://github.com/asheshgoplani/agent-deck (internal/session/cursor_hooks.go)
- https://github.com/tuo-lei/vibe-replay/issues/577 (`turn_ended` and new state fields, 2026-09-08) , https://vibe-replay.com/blog/cursor-local-storage/
- https://forum.cursor.com/t/critical-cursor-helper-retrieval-always-local-writing-30gb-automatically-on-launch-mac/156061 (extension host names in 2.6.21)
- https://code.visualstudio.com/docs/copilot/customization/hooks , https://docs.devin.ai/desktop/cascade/hooks
- Installed bundle: `/Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js` (`composerWakelockManager.js`, `workspace-paths.ts`), `out/main.js` (`powerMainService.js`), `extensions/cursor-agent-host/dist/main.js` (TranscriptStore).
- Raw downloads and the two idle samples: `raw/` in this folder.
