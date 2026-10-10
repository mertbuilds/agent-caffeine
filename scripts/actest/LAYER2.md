# Layer 2: fresh install and onboarding

These rows have no test file yet. Layer 1 (the new features work) comes first. The ids are the ids of the test inventory.

A row here needs a second user account, a spare Mac or a virtual machine. The runner cannot see a first launch on the Mac it runs on: the app under test is already installed and set up there.

## Install and update (INST)

| id | What | Needs |
|---|---|---|
| INST-01 | Fresh install from the dmg: window art, no Gatekeeper block, the setup window opens once, the name on disk is capitalised | A second user account or a spare Mac, the dmg downloaded in Safari |
| INST-02 | Paths of a fresh install: hooks, plugin files and the link hold the capitalised path | After INST-01 |
| INST-03 | Open from the dmg, from Downloads, from an external drive: the Move to Applications paths | The dmg, a copy in Downloads, a copy on a drive |
| INST-04 | A move onto an existing lowercase install: one bundle, hooks and link still current | A lowercase install and a new copy in Downloads |
| INST-05 | Sparkle update: the name of the bundle, the helper, the login item, the licence and the settings stay. Same event as HELP-15 | The older release installed with helper, hooks, login item and licence |
| INST-06 | Sparkle update over two versions, with the helper fallback of HELP-16 | 1.0.0 installed |
| INST-07 | Update under a hold with the lid closed | The older release, the helper, a hold, an update waiting |
| INST-13 | Trial start: 7 days from the first launch, said in the setup window and in Settings | A fresh user account |
| INST-14 | Last day and end of the trial: one notification each, then no hold | A spare account or a virtual machine with the clock moved |
| INST-15 | The clock set back gives no new trial | As INST-14 |
| INST-16 | Buy, key mail, activate | The real checkout or the Polar sandbox |
| INST-17 | One key on a second Mac: the limit text | A second Mac or user account |
| INST-19 | Deactivate this Mac, activate again | A licence |
| INST-22 | Polar cannot be reached at activation: the error text, no crash | Network off |
| INST-23 | Open at login | A restart of the Mac |
| INST-26 | Settings carried over by an update | The older release with changed settings |

Left for later, because they need a release, the tap or a long wait: INST-08 to INST-12, INST-18, INST-20, INST-21, INST-24, INST-25.

## First run and interface (UI)

| id | What | Needs |
|---|---|---|
| UI-11 | The setup window: agents found, hooks, Set up for agents, helper, login box, Skip. Skip registers nothing | A fresh account, or Show setup again |
| UI-01 | Every headline state of the menu matches the state of the app | Rides on the layer 1 tests: the state file gives the headline kind, the owner reads the text |
| UI-02 | The menu bar icon in each state, on the built-in and an external display, light and dark | Eyes |
| UI-03 | The battery line: colours and text at three charges | On battery |
| UI-09 | Every tab of Settings: every control does what its label says | Eyes, 12 minutes |
| UI-12 | Hide the menu bar icon, open the app again from Spotlight | Eyes |
| UI-13 | Light, dark, accent, contrast, reduced motion | Eyes |
| UI-14 | VoiceOver and the keyboard | Ears |
| UI-19 | Time format and language of the Mac | A setting of macOS changed and put back |
| UI-20 | A crowded menu bar, a notch, a menu bar manager | Eyes |

## Helper setup on a fresh Mac (HELP)

| id | What | Needs |
|---|---|---|
| HELP-01 | Set up the helper: one approval, once | A signed build, no helper yet |
| HELP-12 | Remove the helper in Settings under a hold | The helper is set up again after |
| HELP-13 | The uninstall steps: nothing of the app stays | A full reinstall after |

## What the runner needs for layer 2

- A way to run on a second user account: the evidence folder and the state file are per user, so this works as it is.
- Key questions with a screenshot the owner takes, stored next to the run. The runner has no such step yet.
- For the trial rows: a build that reads its trial start from a test setting. The runner must never move the clock of the owner's Mac.
