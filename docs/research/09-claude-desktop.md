# 09 - Claude desktop: how to detect working, waiting, idle

Date: 2026-10-08. Mac of the owner. Claude 2.26454.2, bundle id `com.anthropic.claudefordesktop`, `/Applications/Claude.app`
(Electron). Embedded Claude Code 2.1.293. Read-only work. No app was started, stopped, clicked or signalled. No prompt was sent.
Only structure was read in the app's data folder: file names, sizes, write times, JSON keys, and the values of
status, state, type, kind, entrypoint, version and pid fields.

Marks: [MAC] measured on this Mac. [BUNDLE] read in the installed code (`app.asar`, the embedded `claude` binary).
[LAB] `caffeinagent --lab-record`, 60 s, Debug build. [INFERRED] not proven. [UNKNOWN] must be measured live.

## 0. What was wrong

[LAB] Before this work the engine saw nothing of Claude desktop. A 60 s recording with the app open and one Code session
idle held 8 `claude` (Claude Code in terminals) and 1 `codex-desktop`, and no line for pid of the app or of its Code session.
Two causes:

1. The catalogue entry `claude-desktop` was a placeholder with no matchers.
2. The embedded Claude Code lies in a bundle: `.../claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`.
   `AgentCatalog.match` drops every process inside `.app/Contents/` that no desktop definition names, so the process
   was never tried against the `claude` definition. Its session file was there and correct, and nobody read it.

The hooks had the same hole: `HookCommand.agentProcess` uses the same catalogue, found no agent above the hook command
and wrote nothing. So a turn in the Code tab did not keep the Mac awake and sent no notification.

## 1. Processes [MAC]

`ps`, 18:05, app open since 17:42, one Code session open and idle:

| Process | Parent | Role |
|---|---|---|
| `Claude.app/Contents/MacOS/Claude` | launchd | main process, the app |
| `Frameworks/Claude Helper.app/.../Claude Helper --type=gpu-process` | main | helper |
| `... Claude Helper --type=utility --utility-sub-type=network.mojom.NetworkService` (also audio, video capture) | main | helper |
| `... Claude Helper --type=utility --utility-sub-type=node.mojom.NodeService` (2 of them) | main | helper |
| `Frameworks/Claude Helper (Renderer).app/.../Claude Helper (Renderer) --type=renderer` (2) | main | helper |
| `Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler` | launchd | helper |
| `Contents/Helpers/disclaimer --pgroup -- <embedded claude and its arguments>` | main | wrapper |
| `~/Library/Application Support/Claude/claude-code/2.1.293/<hash>/claude.app/Contents/MacOS/claude ...` | `disclaimer` | one Code session |
| `npm exec <server> mcp` | embedded `claude` | MCP server of the session |

Other binaries in the bundle, not running then: `Helpers/app-cu-helper`, `Helpers/chrome-native-host`,
`Helpers/permission-fixer`, `Helpers/Claude iOS Sim.app`, `Resources/app.asar.unpacked/resources/github-mcp/github-mcp-server`,
`Frameworks/Claude Helper (GPU).app`, `Claude Helper (Plugin).app`.

The embedded `claude.app` has `LSBackgroundOnly = true` (its `Info.plist`), and `lsappinfo` does not list it. The main
process is `ApplicationType = Foreground` with bundle path `/Applications/Claude.app`. So "go to the agent" from the
embedded process goes up: `claude` -> `disclaimer` -> `Claude`, the first app with windows.

## 2. Code tab: the embedded Claude Code

Arguments of the embedded process (flags and their config values) [MAC]:
`--output-format stream-json --verbose --input-format stream-json --effort <x> --model <x> --permission-prompt-tool stdio
--allowedTools <list> --disallowedTools <list> --setting-sources=user,project,local --permission-mode default
--include-partial-messages --await-initialize --replay-user-messages --settings <json with deniedMcpServers ...>`.
Environment: `CLAUDE_CODE_ENTRYPOINT=claude-desktop`.

- [MAC] It writes a normal session file `~/.claude/sessions/<pid>.json`. Keys: `pid, sessionId, cwd, startedAt, procStart,
  version, kind, entrypoint, hostSessionId, status, statusUpdatedAt, updatedAt, name, nameSince, nameSource, peerProtocol,
  peerFeatures, messagingSocketPath, pidDomain`. Values seen: `entrypoint: "claude-desktop"`, `kind: "interactive"`,
  `status: "idle"`, `version: "2.1.293"`. A terminal session has `entrypoint: "cli"`.
- [BUNDLE] In stream-json mode the status comes from the session state of the SDK:
  `{running: "busy", requires_action: "waiting", idle: "idle"}`. With `waiting` it also writes `waitingFor`:
  `"input needed"` for a question or a dialog, else `"permission prompt"`. So an approval that the desktop app shows
  (`--permission-prompt-tool stdio`) still sets `waiting` in the session file. `shell` is written by the terminal UI only.
  [UNKNOWN] `busy` and `waiting` were not seen live for a desktop session: no prompt was sent.
- [MAC] `--setting-sources=user,project,local`: the user settings are loaded, so the Claude Code hooks in
  `~/.claude/settings.json` apply. The owner has the Agent Caffeine hooks there. [MAC] The hook folder held no file for the
  embedded pid: the catalogue hole of section 0, and no turn ran. [UNKNOWN] that each hook event fires in this mode,
  above all `Notification` with `permission_prompt`. The session file does not depend on it.
- [MAC] One process per Code session (`hostSessionId` in its file, `CLAUDE_CODE_HOST_SESSION_ID` in its environment).
  It stayed alive and idle for more than 32 minutes after its start. [BUNDLE] The app stops an idle session process after
  an idle time-out and starts it again on the next prompt (`desktop_ccd_session_idle_paused`, `idle_timeout_ms`,
  `desktop_ccd_session_idle_warm_start`). The length of the time-out was not read.
- [MAC] Per session the app also keeps `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/local_<uuid>.json`
  (keys: `sessionId, cliSessionId, cwd, lastActivityAt, completedTurns, permissionMode, isArchived, ...`). It has no
  field that says running or idle. Not used.

## 3. The app's own sleep assertion [BUNDLE]

`powerSaveBlocker.start("prevent-app-suspension")` is called in one place. It is one blocker for a set of claims, held by
the main process while the set is not empty and the workspace setting `keepAwakeEnabled` is not false. The claims:

| Claim | When |
|---|---|
| `code_turn` | a Code session is in a turn. Taken at the start, given up 30 s after the last turn ended (`Zcr = 3e4`). Also for a background task or a loop of a session, for at most 2 hours. Settings `ccKeepAwakeWhileWorking`, `ccKeepAwakeOnBattery`. Log: `[keep-awake] code session hold taken`. |
| `code_session:<id>` | the user asked one session to keep the Mac awake ("manual hold") |
| `remote-tools-device` | a tool call for a remote session runs on this Mac |
| `wake_hold:<n>` | the wake scheduler (scheduled tasks) |
| wake scheduler approval | while macOS asks to approve its login item |
| `keepAwakeEnabled` | a preference of the user: held for as long as the app is open |

[MAC] No assertion of the app at idle (`pmset -g assertions`, three reads). [UNKNOWN] the name and type as macOS lists it
(Cursor, also Electron: `NoIdleSleepAssertion` named "Electron").

`swift_addon.node` (the VM of Cowork) imports `IOPMAssertionCreateWithName` and `IOPMAssertionRelease`. [UNKNOWN] when it
takes an assertion and which process owns it. No claim on the Electron blocker names Cowork.

## 4. Cowork / local agent mode

- [BUNDLE] Cowork runs in a VM of Apple's Virtualization framework, started in process by `swift_addon.node`
  (`VZVirtualMachine`). The VM itself is the XPC service `com.apple.Virtualization.VirtualMachine`, a child of launchd, not of
  Claude (the app's own diagnostics find it with `pgrep -f`). The VM image is `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle`.
  `Resources/smol-bin.arm64.img` is in the app bundle.
- [MAC] On this Mac `vm_bundles` does not exist and no VM process runs: Cowork was never started here.
  `vm-support-probe.json` has the keys `key, hardwareKey, virtSupport`.
- [MAC] `local-agent-mode-sessions/<uuid>/<uuid>/` holds `scheduled-tasks.json` and `rpm/manifest.json`
  (keys `lastUpdated, plugins`). `manifest.json` was rewritten with no user action (17:43, 18:03): idle noise. No file there
  has a status field. Nothing in the data folder was written in a 2 minute window at idle but `Cookies` and network state.
- [UNKNOWN] everything about a running Cowork task: whether the agent loop writes a session file on the host (it runs in
  the VM, so most likely not), whether the app or the addon holds an assertion, whether the VM is stopped at idle.

## 5. Chat

- [BUNDLE][INFERRED] A chat answer is made on Anthropic's servers and drawn by a renderer. No keep-awake claim is for chat.
  No local state file exists for it. So chat is not local work, and CPU of the app says nothing: the renderer is busy
  when text streams in and when the user scrolls.
- Local work that a chat can start: an MCP server of `claude_desktop_config.json` (a child process of the app), and computer
  use (`Helpers/app-cu-helper`, `computer_use.node`). [UNKNOWN] what computer use looks like while it runs.

## 6. What the engine does now

1. Catalogue `claude-desktop`, display name "Claude", `verified: true`. Engine: the main binary `Claude.app/Contents/MacOS/Claude`
   in any folder. Session: a binary `claude.app/Contents/MacOS/claude` (the embedded Claude Code). Helpers: everything under
   `Claude.app/Contents/Frameworks/`, `Helpers/` and `Resources/`.
2. Each Code session is its own line of the agent "Claude", with the state of its session file: `busy` working, `waiting`
   waiting for you, `idle` idle. It is never a "Claude Code" line. An embedded process with no session file is no session
   (it starts up, or runs one command). A Claude Code at another path whose session file says `entrypoint: claude-desktop`
   is moved to "Claude" too.
3. The app itself (chat, Cowork) is one more instance, judged by activity, with its CPU set aside as for Cursor. Its signs:
   a child command that is busy (an MCP server of the chat), and the app's own assertion. The assertion counts only after
   45 s in a row with no Code session in a turn (`EvidenceCollector.claudeAppHoldSettle`): the `code_turn` claim is held
   for 30 s after a turn, and the session file tells that turn already. With Code sessions open, the app has its own line
   only when it showed one of these signs in the last hour, so the panel shows the sessions and no extra idle line.
4. Hooks: the hook agent `claude` covers `claude-desktop`. The hook command lands on the embedded process, the same instance
   as the session file. "Own state newer than the hook wins" applies as for the CLI.
5. Notifications and "go to the agent" follow each session's turn and go to Claude.app.

[LAB] After: the same 60 s check gives one line `claude-desktop` "Claude", role session, pid of the embedded process,
`rep: idle` from `claudeSession`, verdict idle "Ready for your next message", `live: true`, 1 child command (its MCP server).
The app has no extra line. The 8 terminal sessions stay "Claude Code".

## 7. Open, and the live test for each

| Open | Live test |
|---|---|
| `busy` in the session file during a desktop turn, and its timing | Send a prompt in the Code tab while `--lab-record` runs. Mark `working` at send, `idle` at the end. |
| `waiting` during an approval | Ask for a command that needs approval. Leave the prompt open for 1 minute. Mark `waiting`. |
| Hook events in stream-json mode | Same runs, with the new build installed. Check `~/Library/Application Support/com.caffeinagent.app/hooks/claude-<pid>.json`. |
| The assertion after a turn stays under 45 s | Same run: `pwr` must not appear on the app line after a Code turn. |
| Cowork: any exact sign | Start a Cowork task of 3 minutes. Record `ps`, `pmset -g assertions`, and the write times in `local-agent-mode-sessions` and `vm_bundles`. |
| Chat: no local sign | Ask a long chat answer. The line must stay idle. |
| `keepAwakeEnabled` on | With the app's "keep awake" preference on, the app line says working for as long as the app is open. Decide if that is wanted. |
| Idle time-out of a Code session process | Leave a Code session idle. Note when its process ends. |
