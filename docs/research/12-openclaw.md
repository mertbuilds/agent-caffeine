# 12 - OpenClaw: what it offers, and what is missing for an exact state

Date: 2026-10-08. Mac of the owner. OpenClaw 2026.9.9, the npm package in `/opt/homebrew/lib/node_modules/openclaw`
(`package.json`: repository `github.com/openclaw/openclaw`). It was installed on this Mac during this work by someone
else, with `openclaw onboard` running in a terminal. We started no OpenClaw process and installed nothing. Nothing was
written below `~/.openclaw`. No config or auth file was opened. Of the owner's state only file names, table and column
names, row counts and the values of state fields were read.

Marks: [PKG] a file of the installed package (path given). [DOC] its docs in `docs/` of the package. [MAC] measured on
this Mac. [UNKNOWN] must be measured live.

## 0. Result

No hook is installed. Since 2026-10-09 the gateway is judged by the state of its sessions, and its own CPU use is no
sign of work: section 7. The text of sections 1 to 6 is from 2026-10-08, before that.

- The database of each agent has the table `session_windows` with a `status` of each session: `running` while a run of
  the session is in progress. One run that ended was measured. A run in progress was not, so the definition stays
  `verified: false`.
- A state database exists and has tables for background tasks and cron runs with a status and a pid.
- Its plugin hooks have exact events. A plugin has to be installed and enabled through `~/.openclaw/openclaw.json`.

## 1. The product and the processes

- The name is "OpenClaw": the title of `README.md` [PKG]. Older names are in `CHANGELOG.md` and the docs: Clawdbot and
  Moltbot [PKG]. `package.json`: `"bin": {"openclaw": "openclaw.mjs"}`, so the one command is `openclaw`. [MAC] No
  `clawdbot` or `moltbot` command and no `~/.clawdbot` or `~/.moltbot` folder is on this Mac. The older names are not
  matched.
- [MAC] `/opt/homebrew/bin/openclaw` is a link to `openclaw.mjs`. The running `openclaw onboard` was two processes:
  `node /opt/homebrew/bin/openclaw onboard`, and below it a process with the title `openclaw` and no arguments left
  (executable `/opt/homebrew/Cellar/node/26.8.1/bin/node`). Node writes a title over argv.
- [MAC] Later the same child had the title `openclaw-gateway`: the onboarding had started the gateway in that process.
  [PKG] `dist/`: `process.title = "openclaw-gateway"`, `"openclaw-node-worker"`, `"openclaw"` and `CLI_NAME`.
- [PKG] `dist/`: the launchd label is `ai.openclaw.gateway`. [MAC] No such agent is in `~/Library/LaunchAgents` yet.
  [UNKNOWN] the argv of the gateway that launchd starts. [DOC] `docs/cli/index.md`: `openclaw gateway` and
  `openclaw gateway run` run the gateway, and `gateway status|install|uninstall|start|stop|restart|call|health|probe|
  discover|usage-cost` manage it.
- [DOC] `docs/cli/index.md`, the command tree: `setup`, `onboard`, `configure`, `config`, `doctor`, `update`, `plugins`,
  `status`, ... run no turn (`AgentCatalog.openClawCommands`). `agent`, `tui`, `chat`, `terminal`, `acp`, `node`,
  `worker`, `cron`, `resume` and a start with no command are left sessions.
- [DOC] `docs/platforms/macos.md`: a Mac app exists that can own the local gateway through launchd. Not installed here.
- [UNKNOWN] Tool commands as children of the gateway, and what an `openclaw-node-worker` is for.

Catalogue (`AgentCatalog`, version 8): definition `openclaw`, name "OpenClaw", level activity, `verified: false`. The
gateway (by its arguments, or by the title `openclaw-gateway`) is an engine: it lives all day and works in turns. A
management command is no agent. Known gap: the child of a management command has the title `openclaw` and no
arguments, so it reads as an OpenClaw session with no sign of work.

## 2. State on disk [MAC] [DOC]

- `~/.openclaw/`: `openclaw.json` (the config, with numbered backups), `agents/<agent id>/sessions/`, `state/`,
  `tmp/`, `workspace/`, `cache/`, `media/`, `migration/`, `plugin-skills/`.
- `state/openclaw.sqlite` with `-wal` and `-shm`: the shared state database, 110 tables. [DOC]
  `docs/gateway/gateway-lock.md`: the process owner is the lock `tmp/openclaw-<uid>/state.<hash>.lock`, and
  `tmp/openclaw-<uid>/gateway.state.lock` holds "the owner's PID, process start identity, role, and runtime port".
- Tables that can hold work in progress, with their columns, all with 0 rows here:
  - `task_runs`: `task_id`, `runtime`, `task_kind`, `status`, `execution_owner_pid`, `execution_owner_start_identity`,
    `created_at`, `started_at`, `ended_at`, `last_event_at`, `tool_use_count`, `last_tool_name`, ...
  - `cron_run_receipts`: `status`, `owner_pid`, `owner_start_time`, `started_at_ms`, `finished_at_ms`, ...
  - `flow_runs`: `status`, `current_step`, `created_at`, `updated_at`, `ended_at`, ...
  - `worker_inference_turns`: `state`, `turn_id`, `run_id`, `created_at_ms`, `updated_at_ms`, ...
  - `subagent_runs`: `run_id`, `child_session_key`, `created_at`, `payload_json`.
- `gateway_boot_lifecycle`: `boot_id`, `pid`, `started_at_ms`, `completed_at_ms`, `outcome`: 1 row, the running gateway.
- [DOC] `docs/concepts/session-state.md`: `session_state_events` is a log of `created`, `human_direct_message`,
  `run_completed`, `run_failed`, ... for watched sessions. It records that a child run ended, not that a turn runs.
- [DOC] `docs/concepts/session.md`: the older store was `agents/<agentId>/sessions/sessions.json` with `updatedAt`, which
  is "last store-row mutation" and no state.
- [UNKNOWN] The values of `task_runs.status`, and whether a turn of the main session (a message from a phone) writes a
  row in any of these tables, or only in the transcript tables. This decides whether a reader is possible.

The database can be read without a write the same way as that of Hermes Agent (`mode=ro&readonly_shm=1`,
docs/research/11-hermes-agent.md): [MAC] the schema above was read that way from the live database.

## 3. Hooks and plugins [DOC]

- Internal hooks (`docs/automation/hooks.md`, `hooks/event-types.md`, `hooks/configuration.md`): a folder with `HOOK.md`
  and a handler, in `~/.openclaw/hooks/` ("managed"), in a workspace, or in a plugin. They run in the gateway process.
  Events: `command:new`, `command:reset`, `command:stop`, `session:compact:before|after`, `session:patch`,
  `agent:bootstrap`, `gateway:startup`, `gateway:shutdown`, `message:received`, `message:transcribed`,
  `message:preprocessed`, `message:sent`. No event for the start or the end of a turn. Loading: "No master flag and no
  enabled entries, extra directories, or tracked installs: Gateway skips directory-hook loading". So a hook folder alone
  does nothing: `hooks.internal` in `openclaw.json` must name it (`openclaw hooks enable <name>`).
- Plugin hooks (`docs/plugins/hooks/reference.md`), registered with `api.on(...)` in a plugin:
  `model_call_started` / `model_call_ended` ("Sanitized provider/model call metadata ... No prompt or response
  content"), `after_tool_call` (observe), `agent_end` ("Observe final messages, success state, and run duration"),
  `session_start` / `session_end`, `before_reset`, `cron_changed` ("added, updated, removed, started, finished,
  scheduled"), `gateway_start` / `gateway_stop`. Gates that must not be registered: `before_agent_run`,
  `before_tool_call`, `before_install` ("Fail closed" after 15 seconds).
- A plugin is installed and enabled with `openclaw plugins install ...` and `openclaw plugins enable <plugin-id>`
  (`docs/plugins/manage-plugins.md`). Both write `~/.openclaw/openclaw.json`.

Decision: no installer. The only way is through `openclaw.json`, which the app cannot keep byte for byte, and no event
was seen to fire. A manual set-up, not built and not tested: a plugin that registers `model_call_started`,
`after_tool_call`, `agent_end` and `session_end` and calls the hook command of Agent Caffeine, enabled by the owner with
`openclaw plugins enable`.

## 4. Approval model [DOC]

`docs/tools/exec-approvals.md`: host commands can need an approval, with allowlists and a "YOLO/strict" workflow. The
approvals are in the state database (`operator_approvals` and others). [UNKNOWN] whether a pending approval is a row
with a state that a reader can use. In the gateway, the time between two messages is no turn and must read as idle.

## 5. Its own sleep prevention [PKG]

`grep` for `caffeinate`, `powerSaveBlocker`, `IOPMAssertion`, `pmset` in `dist/` and `docs/`: `caffeinate` only as one
of the wrapper commands its shell parser knows, and `pmset` only in a troubleshooting page that tells the user to turn
sleep off on an always-on host. OpenClaw takes no assertion of its own.

## 6. What the engine says now, and what to measure

Measured here (`--lab-record`, Debug build, 61 seconds): the gateway with the title `openclaw-gateway` read
`openclaw idle (noActivity)`, and `node ... openclaw onboard` was no agent. A gateway at rest does not hold the Mac. A
turn in it holds only through the signs of activity: processor use, and a command below it that is busy. A model wait
and a quiet tool call are not seen. That is the missing part.

To measure, with the gateway running and the owner sending the messages:

1. One message from a phone or `openclaw agent --message ...`: which tables of `state/openclaw.sqlite` get a row at the
   start and change at the end (`task_runs`, `worker_inference_turns`, the transcript tables), and the values of their
   `status` or `state`.
2. A cron job and a heartbeat: `cron_run_receipts.status` while it runs.
3. The process tree during a tool call: children of `openclaw-gateway`, and an `openclaw-node-worker`.
4. The argv of the gateway under launchd after `openclaw gateway install`.

With (1) a reader like `HermesStateReader` is small: the rows carry `execution_owner_pid` and times.

## 7. The gateway at rest read as working: the record, the reader and the rule (2026-10-09)

### What was measured [MAC]

`--lab-record openclaw-long`, 2026-10-08, 419 seconds, 192 samples, gateway pid 6256 (title `openclaw-gateway`), one
sample each 2.2 seconds. The owner reported that the OpenClaw row said "working" with no work.

- The record is not a gateway at rest from start to end. The database of the agent says that one run of a session
  started 20.6 seconds into the record and ended 3.5 seconds later (`session_windows`: `started_at`, `ended_at`,
  `status` `done`, `chat_type` `direct`; the session was made by a `human` actor 0.5 seconds before). No run came
  after it.
- Around the run: 17.6 percent of a core in a sample 4 seconds before it, 197 percent in the sample of the run (4.4 CPU
  seconds), then 23 and 15 percent. 0.78 MB and 0.67 MB were written. A second child process came with the run
  (`cmds` 1 to 2: `node .../openclaw/dist/infra/sqlite-readonly-location.worker.js`) and stayed. No child command read
  as busy in any sample.
- At rest, from 30 seconds to the end (177 samples): 1.6 percent of a core in the mean, 1.3 percent in the median,
  2.1 percent at the 90th percentile, 16 percent in the highest sample. In fixed windows of 5 seconds: 10 of 78
  windows at 2 percent or more, 3 at 3 percent or more, the highest 8.8 percent. Every 30 seconds 16 KB are written:
  the lease `gateway-owner` in `state_leases` of the state database has a `heartbeat_at`.
- The verdict of the app: `idle noActivity` until 28 seconds, then `working cpuActivity` in all 178 samples to the end.
  The CPU rule (3 of the last 6 windows of 5 seconds at 2 percent, `VerdictRules.weakCPUFraction`) held for the first
  time 4 seconds after the run had ended, and then again and again until 265 seconds, because the rest use of the
  gateway is at the threshold. Each time starts the release time of 300 seconds again. So a gateway at rest holds the
  Mac until `weakEvidenceCap` (30 minutes) says that CPU use was the only sign.
- No threshold repairs this. Replayed over the record, the rule holds at 2, 3, 4, 5, 6 and 8 percent (after the run,
  until 45 to 54 seconds) and not at 10 percent, and a run of 3.5 seconds is not seen at any threshold: it fills one
  window. The CPU of the gateway also rises when a client connects, which is no turn.

### The signal [PKG] [MAC]

- File: `~/.openclaw/agents/<agent id>/agent/openclaw-agent.sqlite` (WAL mode), one per agent. Table
  `session_windows`, one row per session.
- [PKG] the schema in `dist/state/openclaw-state-read.worker.js`: `status TEXT CHECK (status IS NULL OR status IN
  ('running', 'done', 'failed', 'killed', 'timeout'))`, `started_at INTEGER`, `ended_at INTEGER`, `updated_at INTEGER`,
  `transcript_updated_at INTEGER`. Epoch milliseconds.
- [PKG] `src/gateway/session-lifecycle-state.ts` (in `dist/session-event-payload-*.mjs`): the lifecycle event `start`
  of a run sets `status: "running"`, `startedAt` and no `endedAt`. The event `end` or `error` sets `done` (success),
  `timeout`, `killed` (cancelled) or `failed`, with `endedAt`. Two ends keep `running` on purpose: a run that the
  restart of the gateway interrupted (it is recovered after the start), and a run that yielded to wait for its child
  runs.
- [MAC] the one run of the record: `status` `done`, `started_at` and `ended_at` 3.5 seconds apart,
  `transcript_updated_at` 17 milliseconds before `ended_at`. `session_nodes.status` said `done` too.
- [PKG] OpenClaw has a watchdog of its own for a run with no progress (`diagnostic-stuck-session-recovery`,
  `STUCK_SESSION_PROGRESS_STALE_MS` 300 000), and the default time limit of a run is 48 hours (`docs/concepts/agent-loop.md`).
- The rows carry no pid. `task_runs` of the state database held 5 rows, all `runtime` `cron`, `status` `failed`, with
  no `execution_owner_pid`: not used.
- The docs in the package (`docs/concepts/session.md`, `session-state.md`) do not describe the column. docs.openclaw.ai
  was not fetched: the package holds the same docs for this version.

### The reader and the rule

- `OpenClawStateReader` reads, for each agent database of `~/.openclaw`, the rows with `status = 'running'` (their
  three times) and the newest `ended_at`. It opens the database as the reader of Hermes Agent does and writes nothing.
  No text and no key of a session is read.
- Only the gateway (role engine) gets the state: it runs the turns, and the rows carry no pid. Working while one row
  says `running`, idle when every database was read and none does. With no database, or with one that cannot be read,
  nothing is said.
- A run that was killed with its process leaves `running` for ever. A row counts only while the newest of
  `started_at`, `updated_at` and `transcript_updated_at` is less than 30 minutes old
  (`OpenClawSummary.runLimit` = `VerdictRules.hookWorkingLimit`). After that the signs of activity decide.
- The gateway's own CPU use is no sign of work (`VerdictRules.countsCPU`), with or without a state. Without a state
  the gateway works only while a command below it is busy or it holds a sleep assertion. The rule is for the gateway of
  OpenClaw alone. The other engines that live all day have a state (Hermes Agent, Codex), and the Codex engine was
  measured at 0.2 percent at rest, far from the threshold. A desktop app is an engine too and has rules of its own.
  A chat in a terminal (`openclaw tui`, `openclaw agent`) is judged as before, CPU use included.
- Replayed (`CaffeinagentTests/Recordings/synthetic-openclaw-gateway.jsonl`, the OpenClaw series of the record alone):
  before, working in 178 of 192 samples and held from 28 seconds to the end. After, idle in all 192 and never held.
  The cut has no state in it, so the replay tests the rule for a gateway with no state, and the 3.5 seconds of the run
  read as idle there. With the reader they read as working.

### What can be missed

- Not measured: a row that says `running`. The values are from the source of 2026.9.9. If another version does not
  write the column, the gateway reads as idle through a turn with no busy command.
- A run that writes nothing for 30 minutes (one tool call or one model wait that long) with no busy command and no
  sleep assertion lets go after 30 minutes.
- A row that stays `running` after a kill holds for up to 30 minutes after its last write, while a gateway lives.
- `openclaw agent --local` runs its turn in its own process. Its row counts for the gateway when one is up. With no
  gateway the process is judged by activity.
- Another state folder (`--profile`, `OPENCLAW_STATE_DIR`, `OPENCLAW_HOME`) is not read: that gateway has no state,
  and only a busy command holds for it.
- With no state that can be read: a model wait, an answer that streams and a tool that runs inside the gateway are
  not seen.
- A worker of the gateway (`*.worker.js`) is a child command. It was never busy in the record. One that is busy for
  10 seconds reads as a running command.

### The test with a real turn (the owner runs it)

The gateway runs. Use the executable `caffeinagent` of a Debug build of this branch (in the app of the build folder,
`Contents/MacOS/caffeinagent`), not the app in the Applications folder: that one does not have the reader yet. In one
terminal:

    <path>/Contents/MacOS/caffeinagent --lab-record openclaw-turn

In a second terminal, with the same executable:

1. Wait 60 seconds. `--lab-mark openclaw idle "gateway at rest"`.
2. Send one message to OpenClaw that takes a minute or more, with a tool call (for example: "run `sleep 90` in the
   shell, then tell me the date"). At the moment of sending: `--lab-mark openclaw working "message sent"`.
3. When the answer is there: `--lab-mark openclaw idle "answer complete"`.
4. Wait 6 minutes. Stop the recording with Control-C.
5. `--lab-score <the file the recorder printed>`.

Expected: the OpenClaw line says `working (reportsBusy)` from the message to the answer, `idle (atPrompt)` before and
after, "wrongly released 0.0 s" and "wrongly held 0.0 s". While the run is in progress, this shows the row (read
only): `sqlite3 "file:$HOME/.openclaw/agents/<agent id>/agent/openclaw-agent.sqlite?mode=ro&readonly_shm=1" "select
status, started_at, ended_at from session_windows"`. If it says `running` then and `done` after, set
`verified: true` and the level `state` in `AgentCatalog`, and copy the recording to `CaffeinagentTests/Recordings/`.
