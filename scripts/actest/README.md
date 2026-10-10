# actest

The guided test runner of Agent Caffeine. The owner does the physical things: closes the lid, pulls the charger, sends a prompt to an agent, looks, listens. The runner says one step at a time, sees what it can by itself, records, judges and cleans up. The assistant reads the result files after and plans the next session.

Python 3.11 or later, standard library only. Not shipped in the app.

    scripts/actest/actest check                 the preflight alone
    scripts/actest/actest list --layer 1        the tests, with the last result per build
    scripts/actest/actest run HELP-21 HELP-02   run tests, in this order
    scripts/actest/actest board                 the result board, as text and as board.html
    scripts/actest/actest report <run-id>       everything recorded for one run
    scripts/actest/actest abort                 stop the run that is under way and clean up
    cd scripts/actest && python3 -m unittest    the self-tests of the runner

`--plain` before the command gives no colour and no screen clearing.

## What the runner may do

It reads: `pmset -g`, `pmset -g batt`, `pmset -g assertions`, `pmset -g sched`, `pmset -g log`, `ioreg`, `ps`, the state file and the status file of the app, and our own files that a test names (the skill of Agent Caffeine, the link to the tool, the marker of the helper, the test job).

It runs: `agent-caffeine` (hold, release, status, skill), its own heartbeat writer, and, for a test with `lab = true`, a lab recording with the binary of the installed app.

It never uses sudo, never writes a power setting, never schedules or cancels a power event, never ends the app or its helper, never drives the screen and never starts an agent. A step that needs one of these tells the owner the exact command and waits for what it then sees.

## The state of the app

The lab recorder runs an engine of its own. What the real app decided is in `.state.json` next to `.status`, which the app writes only while a hidden switch is on:

    defaults write com.caffeinagent.app StateForTests -bool true

`actest check` says when the installed build has no state export, and when the switch is off. `agent-caffeine status --json --detail` prints the same state. The file holds kinds, numbers and times: no name of a session, no folder, no reason of a hold, no name of a job.

## A test is a file

`tests/<area>/<id>.toml`, with the ids of the test inventory. See the head of `actestlib/catalog.py` for the keys, `actestlib/expr.py` for the conditions (`lid=closed`, `app.agent[grok].state=working`) and `actestlib/judge.py` for the pass rules (`within 65s after step 2: sleepdisabled=0`).

## The evidence

`~/Library/Application Support/Agent Caffeine Tests/runs/<date>-<id>-<n>/`: `run.json`, `timeline.jsonl` (one line per second), `heartbeat.txt`, `pmset-log.txt`, `verdict.json`, and `lab.jsonl` when a lab recording ran. The board is made from the verdict files. Nothing is written into the folder of the app.

`LAYER2.md` lists the fresh install and onboarding rows that have no test file yet.
