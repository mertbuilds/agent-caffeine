# 11 - Hermes Agent: how to detect working and idle

Date: 2026-10-08. Mac of the owner. Hermes Agent of Nous Research, source checkout `d94b70f675` (2026-10-08) in
`~/.hermes/hermes-agent`. We started no Hermes Agent process. During this work an install, a `hermes setup`, the gateway
service and a chat were started on this Mac by someone else, and they were only observed. Nothing was written below
`~/.hermes`. No config, env or auth file was opened. Of the files of the owner only names, sizes, write times, JSON keys,
table and column names, pids, counts and the values of state fields were read.

Marks: [SRC] the source in `~/.hermes/hermes-agent` (path given). [DOC] its docs in `website/docs`. [MAC] measured on this
Mac. [TMP] measured in a temp folder with made-up data. [UNKNOWN] must be measured live.

## 0. Result

Hermes Agent has an exact state on disk that needs no install. Every turn takes a row in a table of `~/.hermes/state.db`,
and the row names the pid of the process that runs the turn. The gateway also writes a count of the turns in progress into
`~/.hermes/gateway_state.json`. `HermesStateReader` reads both, and Hermes Agent is a `.state` agent.

It also has a plugin API with exact events. A plugin has to be enabled in `config.yaml`, so we install none (section 3).

A wait for the user (an approval, a question) is not in the files. Such a turn reads as working (section 4).

## 1. The product and the processes

- The name is "Hermes Agent": the title of `README.md` [SRC], and `name = "hermes-agent"` in `pyproject.toml` [SRC].
- [SRC] `pyproject.toml` `[project.scripts]`: `hermes = "hermes_cli.main:main"`, `hermes-agent = "agent.legacy_cli:main"`,
  `hermes-acp = "acp_adapter.entry:main"`. So the command is `hermes`. The catalogue matched only `hermes-agent` and did
  not see a `hermes` at all.
- [MAC] `~/.local/bin/hermes` is a shell script of 77 bytes: `exec ~/.hermes/hermes-agent/.hermes/bin/hermes "$@"`. That
  file is a shell script too: `exec ~/.hermes/tools/python-3.14.7+20260901-darwin-arm64/bin/python3 -I -c '<source>' "$@"`.
  The source is about 7,000 characters and ends in `from hermes_cli.main import main`, `sys.exit(main())`.
- [MAC] So a running Hermes Agent is one Python process with no script name in argv. Seen for `hermes setup`, a chat and
  the gateway: executable `~/.hermes/tools/python-3.14.7+20260901-darwin-arm64/bin/python3.14` (the `txt` line of `lsof`),
  argv `<...>/bin/python3 -I -c <source> <arguments>`. The title stays that of Python. [SRC] `hermes_cli/main.py`
  `_set_process_title`: the title `hermes` is set only with the optional package `setproctitle`, and on macOS the fallback
  changes only the thread name. [MAC] This install has no such title.
- [MAC] The gateway service is the launchd agent `ai.hermes.gateway` (`~/Library/LaunchAgents/ai.hermes.gateway.plist`;
  [SRC] `hermes_cli/gateway.py`: `ai.hermes.gateway-<profile>` for a profile). Two processes:
  `python3 -I -c <source> --run-module hermes_cli.stderr_timestamp --error-log <log> -- <hermes> gateway run
  --external-supervisor`, and below it the gateway itself, `python3 -I -c <source> gateway run --external-supervisor`. The
  pid in `gateway_state.json` is that of the second. [SRC] `hermes_cli/gateway.py`: the service runs
  `gateway run --replace` in other set-ups.
- [SRC] The top-level commands are the parsers in `hermes_cli/subcommands/`. Those that run no turn are listed in
  `AgentCatalog.hermesCommands` (`setup`, `update`, `doctor`, `config`, `plugins`, ...). `chat`, `resume`, `acp`, `cron`,
  `serve`, `dashboard`, `desktop`, `gateway run` and a start with no command can run a turn.
- [MAC] `/Applications/Hermes.app` is the installer: bundle identifier `com.nousresearch.hermes.setup`, one binary
  `Contents/MacOS/Hermes-Setup` (11 MB), no other code. It is no agent and is not matched.
- [SRC] A desktop app exists in the source (`apps/desktop`, Electron, `productName` "Hermes"). It is not installed on this
  Mac. [UNKNOWN] its process shape, and how its Python backend is started. If the backend is started through the launcher
  it is matched as Hermes Agent, and its turns have rows with its pid.
- [UNKNOWN] Tool commands as children of the process: no turn was run by us. [MAC] The gateway had no child at rest.
- [MAC] Other software named Hermes: the JavaScript engine of React Native is a binary `hermes` (and `hermesc`), and
  Hermes.app can be another vendor's app. A binary is never matched as Hermes Agent, only Python that runs the launcher
  source, a script `hermes`, the module `hermes_cli`, or the old name `hermes-agent`.

Catalogue (`AgentCatalog`, version 8): definition `hermes-agent`, name "Hermes Agent". New matchers: `.inlineSource` (the
source of `python -c` contains `from hermes_cli.main import main`) and `.script` (an interpreter runs a script of this
name). `gateway run` is an engine. `--run-module ...` and the other `gateway` commands are helpers. A management command
is no agent.

## 2. State with no install

### The turn lease [SRC]

- `hermes_state_common.py`: `CREATE TABLE IF NOT EXISTS session_turn_leases (conversation_id TEXT PRIMARY KEY, holder TEXT
  NOT NULL, acquired_at REAL NOT NULL, expires_at REAL NOT NULL)`, in `state.db` of the Hermes home.
- `agent/turn_facade_lease.py`: "Durable cross-process session turn lease for `TurnFacadeMixin.run_conversation`. One
  process at a time may load -> run -> flush a session shared through state.db (Desktop, CLI resume, gateway, background
  delivery)". `admit_durable_turn_lease` takes the row before the turn, also when the session has no row yet.
  `holder = f"pid={os.getpid()}{holder_namespace_token()}:turn={relay_turn_id}:platform={...}"`. `LEASE_TTL_SECONDS = 300`,
  renewed every 60 seconds (`refresh_interval`). `DurableTurnLease.release` deletes the row at the end of the turn.
- `hermes_state_pidns.py`: the `:pidns=<id>` part is added only inside a pid namespace (Linux containers).
- No lease is taken when the agent has no session database or `_persist_disabled` is set (`admit_durable_turn_lease`).
  [UNKNOWN] which runs that is. So a process is said to be idle only when its turns are known to be in the files (below).
- The times are `time.time()`: epoch seconds.

### The gateway state [SRC] [MAC]

- `gateway/status.py`: `_RUNTIME_STATUS_FILE = "gateway_state.json"` in the Hermes home. `_build_runtime_status_record`:
  `pid`, `kind` (`hermes-gateway`), `argv`, `start_time`, `hermes_home`, `gateway_state`, `exit_reason`,
  `restart_requested`, `active_agents`, `platforms`, `session_store`, `updated_at`, `code_sha`, `code_version`.
- `gateway/run.py` `_persist_active_agents`: "Persist the live in-flight agent count to `gateway_state.json` at every turn
  boundary". `gateway/run_shutdown.py` `_active_work_count`: running agents + cron jobs + API runs + deferred agent workers.
- `derive_gateway_busy`: "Busy iff live, serving (`running`/`degraded`), and `active_agents > 0`".
- `_RUNTIME_STATUS_STALE_TTL_S`: a housekeeping thread stamps `updated_at` every 60 seconds. That write is noise.
- [MAC] The file of the running gateway: the keys above plus `multiplex_standalone_reason`, `served_profiles`,
  `active_work`. `gateway_state` was `running`, `active_agents` 0, and `pid` was the pid of the gateway process.
  `gateway.pid`, `gateway.lock` and `gateway.sock` are next to it.

### The open chats [SRC] [MAC]

- `hermes_cli/active_sessions.py`: "this module records currently open chat surfaces, including idle CLI/TUI sessions that
  have not written a transcript row yet". File `runtime/active_sessions.json`, `{"entries": [...]}` (a bare list is also
  read by Hermes Agent), each entry with `lease_id`, `session_id`, `surface`, `pid`, `process_start_time`, `started_at`,
  `updated_at`. [MAC] The file exists with an open chat.

### Reading the database without a write [TMP] [MAC]

- `state.db` is in WAL mode: [MAC] `state.db-wal` and `state.db-shm` are next to it while Hermes Agent runs. A new row is
  in the WAL until a checkpoint.
- [TMP] A normal read-only SQLite reader (`mode=ro`) changed byte 104 of `-shm` at each read (its read mark). With
  `mode=ro&readonly_shm=1` and the reader in a process of its own, it saw the newest rows and changed no byte. Inside one
  process SQLite shares the index, so this shows only across processes
  (`HermesStateReaderTests.testAReaderLeavesNoMarkInTheFilesOfTheAgent`).
- So the reader opens the database with `mode=ro&readonly_shm=1` while a WAL is there, and with `immutable=1` when there
  is none. It makes no file. A WAL with no `-shm` is not read.
- [MAC] On the live database one open and one query took 0.24 ms, and the WAL was not written in 20 seconds of a gateway
  at rest. The database is read again only when it or its WAL was written.

### Profiles [SRC]

`get_hermes_home() / "state.db"`: each profile has a home of its own below `~/.hermes/profiles/<name>`, with its own
`state.db`, `gateway_state.json` and `runtime/`. The reader reads the default home and each profile. `HERMES_HOME` moved
to another place is not found.

### What the reader says

- Working: a row whose `holder` has the pid of this process, taken after the process started, and not run out for more
  than 120 seconds. Or `gateway_state.json` with this pid, a serving state and `active_agents > 0`.
- Idle: no such row, every database read, and the process is known: it is in `active_sessions.json`, it is the gateway of
  `gateway_state.json`, or it had a row before.
- Nothing: any other process (a one-shot run before its first row). The signs of activity decide, as before.
- The time a turn ended is not in the files. The collector keeps the time of the sample in which the row was gone.

Idle noise: the gateway writes `gateway_state.json` once a minute and uses the processor in bursts. Neither is work: the
count is 0 and no row is held.

## 3. Hooks and plugins [DOC] `user-guide/features/hooks.md`, `plugins.md`

Four systems:

| System | Where | Runs in | Opt-in |
|---|---|---|---|
| Gateway hooks | `~/.hermes/hooks/<name>/HOOK.yaml` + `handler.py` | gateway only | placing the files |
| Plugin hooks | `~/.hermes/plugins/<name>/plugin.yaml` + `__init__.py`, `ctx.register_hook()` | CLI and gateway | `plugins.enabled` in `config.yaml` |
| Shell hooks | `hooks:` block in `config.yaml` | all | `config.yaml` |
| Outbound webhooks | `hooks.outbound:` in `config.yaml` | CLI and gateway | `config.yaml` |

- Gateway hook events: `gateway:startup`, `session:start`, `session:end`, `session:reset`, `agent:start` ("Agent begins
  processing a message"), `agent:step`, `agent:end`, `command:*`. Handlers run in the gateway process and are loaded once,
  at gateway start. "The CLI, TUI, Desktop and cron never load gateway hooks."
- Plugin hooks (`hermes_cli/plugins.py` `VALID_HOOKS` [SRC]) that follow a turn: `pre_llm_call` ("Once per turn before the
  loop"; it can inject context, a callback that returns nothing is passive), `pre_api_request` / `post_api_request` (per
  model call), `post_tool_call`, `on_session_end` ("Canonically at each turn finalization", with `completed`, `failed`,
  `interrupted`), `agent_loop_stopped` (an interrupt), `on_session_finalize`. A callback gets keyword arguments with
  `session_id`, `turn_id`, `platform`. Callbacks of the hot path are cut off after `plugins.hook_callback_timeout` (30 s).
  A `pre_tool_call` that times out blocks the tool: it must not be registered.
- "General plugins and user-installed backends are disabled by default": nothing loads "until you add the plugin's name to
  `plugins.enabled` in `~/.hermes/config.yaml`", or `hermes plugins enable <name>`.
- [MAC] `~/.hermes/plugins/` of the owner holds the plugins of two other tools, each a `plugin.yaml` and an `__init__.py`.

Decision: no installer. The plugin file itself could be ours, but it does nothing until `config.yaml` is edited, and the
app cannot keep a YAML file byte for byte. The lease gives the same turn with no install. What only a plugin would add is
the wait (section 4). A manual set-up for that, not built and not tested:

1. A folder `~/.hermes/plugins/agent-caffeine/` with a `plugin.yaml` (name, version) and an `__init__.py` whose
   `register(ctx)` registers `on_human_input_request`, `on_human_input_resolved`, `on_session_end` and
   `agent_loop_stopped`, each calling the hook command of Agent Caffeine with the pid.
2. `hermes plugins enable agent-caffeine`, run by the owner.

## 4. Approval model [DOC]

- `on_human_input_request` "Fires right before Hermes blocks waiting for a person to type or click something", kinds
  `sudo`, `clarify`, `approval`, on the CLI, the TUI, the desktop app, ACP and the gateway platforms.
  `on_human_input_resolved` fires exactly once per request. `pre_approval_request` / `post_approval_response` are for
  command approvals. So the wait is visible to a plugin only.
- [UNKNOWN] On disk: nothing was found that says the wait. The row of the turn stays while the turn is blocked, so a turn
  that waits for an answer reads as working, in the terminal and in the gateway. The Mac stays awake until the answer or
  the time limit of the prompt.
- In the gateway, "waiting for the next message" is no turn: no row and a count of 0. That is idle.

## 5. Its own sleep prevention [SRC]

`grep` for `caffeinate`, `IOPMAssertion`, `powerSaveBlocker`, `pmset` in the source without tests: only
`apps/desktop/electron/power-save.ts` (Electron `powerSaveBlocker`, `prevent-app-suspension`, behind a `keepAwake`
setting) and `apps/desktop/electron/main.ts`. The CLI and the gateway take no assertion. [UNKNOWN] when the desktop app
holds its blocker.

## 6. What was measured, and what was not

Measured here with the engine (`--lab-record`, Debug build, 61 seconds, the processes as they were): the chat in a
terminal read `hermes-agent idle (atPrompt)`, the gateway read `hermes-agent idle (atPrompt)`, and the wrapper of the
gateway and `Hermes-Setup` were no agent. So the matching, the gateway file, the open-chat file and the read of the live
`state.db` work on a real install.

Not measured: a turn. The row was never seen in a real database, only in the source. To measure:

1. A prompt in `hermes` with a quiet command (`sleep 120`): a row with `pid=<pid of the chat>` in `session_turn_leases`
   from the prompt to the answer, and "Working on a task" in the menu for the whole time.
2. A message to the gateway from a phone: `active_agents` 1 and a row with the pid of the gateway, then 0 and no row.
3. A cron job that calls a model: `active_agents` above 0 while it runs. Whether it also takes a row.
4. Esc in the middle of a turn: the row is gone at once.
5. An approval prompt: the row stays (working). How long the prompt waits.
6. `hermes chat -q "..."`: whether a one-shot run takes a row.
7. Whether tool commands are children of the Python process.
