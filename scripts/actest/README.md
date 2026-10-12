# actest

The guided test runner of Agent Caffeine. The owner does the physical things: closes the lid, pulls the charger, sends a prompt to an agent, looks, listens. The runner says one step at a time, sees what it can by itself, records, judges and cleans up. The assistant reads the result files after and plans the next session.

Python 3.11 or later, standard library only. Not shipped in the app.

    scripts/actest/actest check                 the preflight alone
    scripts/actest/actest list --layer 1        the tests, with the last result per build
    scripts/actest/actest list --busy           only the tests that can start as the agents are now
    scripts/actest/actest run HELP-21 HELP-02   run tests, in this order
    scripts/actest/actest board                 the result board, as text and as board.html
    scripts/actest/actest report <run-id>       everything recorded for one run
    scripts/actest/actest abort                 stop the run that is under way and clean up
    cd scripts/actest && python3 -m unittest    the self-tests of the runner

`--plain` before the command gives no colour and no screen clearing.

## What the runner may do

It reads: `pmset -g`, `pmset -g batt`, `pmset -g assertions`, `pmset -g sched`, `pmset -g log`, `ioreg`, `ps`, three hidden defaults of the app with `defaults read` (`StateForTests`, `ClosedLidLimitSecondsForTests` and `OfflineLimitSecondsForTests`), the state file and the status file of the app, and our own files that a test names (the skill of Agent Caffeine, the link to the tool, the marker of the helper, the test job). For a test with `watch = ["claude"]` it also reads two keys of each `~/.claude/sessions/<pid>.json`, `status` and `statusUpdatedAt`, and keeps nothing else of the file: not the folder and not the name of the session. For a test with `watch = ["sessions"]` it reads `pid`, `kind`, `status` and `statusUpdatedAt` of each of those files and compares the pids that live in `ps` with the Claude rows of the app. It keeps a count and the pids that have no row.

It runs: `agent-caffeine` (hold, release, status, skill), its own heartbeat writer, and, for a test with `lab = true`, a lab recording with the binary of the installed app.

It never uses sudo, never writes a power setting, never schedules or cancels a power event, never ends the app or its helper, never drives the screen and never starts an agent. A step that needs one of these tells the owner the exact command and waits for what it then sees.

## The state of the app

The lab recorder runs an engine of its own. What the real app decided is in `.state.json` next to `.status`, which the app writes only while a hidden switch is on:

    defaults write com.caffeinagent.app StateForTests -bool true

The state has the closed-lid period too (`app.closedLid.heldSeconds`, `app.closedLid.limitSeconds`, `app.closedLid.stop`, and `app.closedLid.agentsReleased` once the limit is reached and agents are let go), and the way to the network with the offline rule (`app.network.online`, `app.network.offlineSeconds`, `app.network.limitSeconds`, `app.network.agentsReleased`). When one of the two rules let go of the agents and nothing else holds, `app.headline` is `agentsStopped` and `app.reason` is `offline`, `closedLidTime` or `closedLidDrop`.

The smallest time limit of the closed lid limit is 1 hour and the smallest time of the offline rule is 5 minutes, so `HOLD-30` and `HOLD-40` tell the owner to set them in seconds with two more hidden defaults, which the app reads at every sample, and to delete them after:

    defaults write com.caffeinagent.app ClosedLidLimitSecondsForTests -int 180
    defaults delete com.caffeinagent.app ClosedLidLimitSecondsForTests
    defaults write com.caffeinagent.app OfflineLimitSecondsForTests -int 60
    defaults delete com.caffeinagent.app OfflineLimitSecondsForTests

The app obeys them only while `StateForTests` is on, and only when they are shorter than the limit of the settings. The runner reads them and never writes them: the cleanup of a run and `actest abort` print the delete command while one is still set, and the preflight has the item "no leftover test limit" for every test but the one that sets that limit. The runner changes no network setting either: in `HOLD-40` the owner turns Wi-Fi off and on, and the runner sees it in `app.network.online`.

`actest check` says when the installed build has no state export, and when the switch is off. `agent-caffeine status --json --detail` prints the same state. The file holds kinds, numbers and times: no name of a session, no folder, no reason of a hold, no name of a job.

## A test is a file

`tests/<area>/<id>.toml`, with the ids of the test inventory. See the head of `actestlib/catalog.py` for the keys, `actestlib/expr.py` for the conditions (`lid=closed`, `app.agent[grok].state=working`, `held.first=true`, `session.state=idle`) and `actestlib/judge.py` for the pass rules (`within 65s after step 2: sleepdisabled=0`).

## Testing while agents work

Agent Caffeine holds the Mac awake most of the day, for the agents of the owner. A test says what it needs of them, and `actest list` shows it for each test:

- `any time`: the test can start while agents work. Most tests are of this kind.
- `needs idle` (`idle = true` under `[needs]`): no agent may work. The `why` of the test says the reason. These are the tests where the Mac must sleep while the app is on, and the tests where the sleep flag must follow one hold.
- `needs sleep` (`sleeps = true`): the app must not hold, and it can be off. The fix is: pause Agent Caffeine or switch it off for this test. While the Mac sleeps, the agents stop.

`actest list --busy` reads the Mac once and lists only the tests that can start now.

A rule with `if idle: ` in front is judged only when Agent Caffeine held nothing before the first step. While an agent works, such a rule is `SKIP` with the reason. It is never a pass. Example: the hold of `CLI-01` is found by its id (`held.hold=true`) and ends at its time while agents work. That the Mac is awake because of this hold (`app.headline=manualHold`) shows on an idle Mac only.

A run can thus end in three ways per rule: pass, fail, skipped. When rules were skipped and the others passed, the verdict and the board say `PASS (partial: 2 checks need an idle Mac)`, and the page lists the rules that were not judged. Run the test again on an idle Mac for the whole pass. A run in which no rule was judged is `SKIPPED`.

The runner looks at the start only. If an agent starts to work in the middle of a run on an idle Mac, a rule for an idle Mac can fail. The measured value says so. Run the test again.

## The evidence

`~/Library/Application Support/Agent Caffeine Tests/runs/<date>-<id>-<n>/`: `run.json`, `timeline.jsonl` (one line per second), `heartbeat.txt`, `pmset-log.txt`, `verdict.json`, and `lab.jsonl` when a lab recording ran. The board is made from the verdict files. Nothing is written into the folder of the app.

`LAYER2.md` lists the fresh install and onboarding rows that have no test file yet.
