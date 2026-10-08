# 12 - OpenClaw: what it offers, and what is missing for an exact state

Date: 2026-10-08. Mac of the owner. OpenClaw 2026.9.9, the npm package in `/opt/homebrew/lib/node_modules/openclaw`
(`package.json`: repository `github.com/openclaw/openclaw`). It was installed on this Mac during this work by someone
else, with `openclaw onboard` running in a terminal. We started no OpenClaw process and installed nothing. Nothing was
written below `~/.openclaw`. No config or auth file was opened. Of the owner's state only file names, table and column
names, row counts and the values of state fields were read.

Marks: [PKG] a file of the installed package (path given). [DOC] its docs in `docs/` of the package. [MAC] measured on
this Mac. [UNKNOWN] must be measured live.

## 0. Result

No exact state of a turn is read, and no hook is installed. OpenClaw is matched better and is still judged by activity.

- A state database exists and has tables for background tasks and cron runs with a status and a pid. No turn ran on
  this Mac, so no row of a turn in progress was seen, and which table says "a turn of the main session runs" is not known.
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
