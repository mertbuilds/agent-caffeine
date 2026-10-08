import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BATTERY_FLOOR,
  BATTERY_LEVELS,
  INITIAL,
  RELEASE_AFTER,
  SPEED,
  WAITING_HOLD,
  advance,
  allowHelper,
  batteryStop,
  clockTime,
  detailOf,
  headlineText,
  iconLabel,
  iconLook,
  lasting,
  preset,
  resume,
  setBattery,
  setChoice,
  setEnabled,
  setLid,
  setMode,
  setPower,
  sleepOutlook,
  sleepOutlookText,
  startPause,
  startReachable,
  stopReachable,
  tickEvery,
  view,
  type SimState,
} from "./simulator";

/** Moves the clock on by simulated seconds. */
function later(state: SimState, seconds: number): SimState {
  return advance(state, (seconds * 1000) / SPEED);
}

/** The mode "always" with no agent open. */
function alwaysOn(): SimState {
  return setMode(setChoice(setChoice(preset(INITIAL, "idle"), "claude", "closed"), "codex", "closed"), "always");
}

test("working sessions keep the Mac awake, idle ones are only counted", () => {
  const shown = view(preset(INITIAL, "working"));
  assert.equal(shown.held, true);
  assert.equal(shown.pose, "awake");
  assert.equal(shown.subtitle, "2 agents are working");
  // Two different agents work, so the count of the headline is the count the reader sees.
  assert.deepEqual(shown.groups.map((group) => group.title), ["Claude Code", "Codex · website"]);
  assert.equal(shown.groups[0].detail, "1 working");
  assert.deepEqual(shown.groups[0].children.map((child) => child.label), ["wiki-6e", "8 idle sessions"]);
  assert.equal(shown.groups[1].detail, "Working for 3 minutes");
});

test("a wait begins when it is set, whatever the clock did before", () => {
  const quit = setChoice(setChoice(preset(INITIAL, "working"), "claude", "closed"), "codex", "closed");
  const asked = setChoice(later(quit, 3600), "claude", "waiting");
  assert.equal(view(asked).held, true);
  assert.equal(view(asked).subtitle, "Claude Code is waiting for you, for at least 5 more minutes");
  assert.equal(view(asked).groups[0].detail, "Waiting for your answer");
  // A wait that ran out begins again when it is set again.
  const released = later(asked, WAITING_HOLD + 300);
  assert.equal(view(released).held, false);
  assert.equal(view(released).groups[0].detail, "Waiting for your answer for 10 minutes");
  const again = setChoice(released, "claude", "waiting");
  assert.equal(view(again).held, true);
  assert.equal(view(again).subtitle, "Claude Code is waiting for you, for at least 5 more minutes");
  // A wait that still holds is left alone.
  assert.equal(setChoice(asked, "claude", "waiting"), asked);
});

test("an agent that waits holds for 5 minutes, then the Mac can sleep", () => {
  const asked = preset(INITIAL, "waiting");
  const first = view(asked);
  assert.equal(first.held, true);
  assert.equal(first.pose, "attentive");
  assert.equal(first.subtitle, "Claude Code is waiting for you, for at least 5 more minutes");
  assert.equal(first.groups[0].detail, "Asked you a moment ago");
  assert.equal(view(later(asked, WAITING_HOLD - 30)).subtitle, "Claude Code is waiting for you, for at least 1 more minute");
  const released = view(later(asked, WAITING_HOLD));
  assert.equal(released.held, false);
  assert.equal(released.pose, "asleep");
  assert.equal(released.subtitle, "Claude Code is waiting for you");
  assert.equal(released.groups[0].detail, "Waiting for your answer for 5 minutes");
});

test("the menu says what Agent Caffeine does, and when the Mac sleeps only with the lid closed on battery", () => {
  const asked = preset(INITIAL, "waiting");
  assert.deepEqual(sleepOutlook(asked), { kind: "letsGo", after: WAITING_HOLD });
  assert.equal(sleepOutlookText(sleepOutlook(asked)), "Agent Caffeine keeps your Mac awake for 5 more minutes");
  // Only the helper keeps the Mac awake with the lid closed on battery.
  const closed = setLid(allowHelper(setPower(asked, "battery")), "closed");
  assert.equal(view(closed).subtitle, "Claude Code is waiting for you, your Mac sleeps in 5 minutes");
  assert.equal(sleepOutlookText(sleepOutlook(closed)), "Your Mac sleeps in 5 minutes");
  assert.equal(view(setPower(closed, "adapter")).subtitle, "Claude Code is waiting for you, for at least 5 more minutes");
  // Another agent works, so nothing is said about sleep.
  const busy = setChoice(asked, "codex", "working");
  assert.equal(view(busy).subtitle, "Codex is working");
  assert.equal(sleepOutlookText(sleepOutlook(busy)), null);
  // The Mac stays awake anyway in the mode "while an agent is open".
  assert.equal(view(setMode(asked, "agentOpen")).subtitle, "Claude Code is waiting for you");
  assert.equal(sleepOutlookText(sleepOutlook(later(asked, WAITING_HOLD))), null);
});

test("a busy command holds after the agent is done", () => {
  const shown = view(preset(INITIAL, "build"));
  assert.equal(shown.held, true);
  assert.equal(shown.subtitle, "Claude Code is working");
  assert.equal(shown.groups[0].detail, "Running 1 command for 3 minutes");
});

test("idle sessions never hold while the mode is working, and hold while it is open", () => {
  const idle = preset(INITIAL, "idle");
  assert.equal(view(idle).held, false);
  assert.equal(view(idle).subtitle, "All agents are idle");
  assert.deepEqual(view(idle).groups.map((group) => group.detail), ["2 idle sessions", "10 idle sessions"]);
  assert.equal(view(setMode(idle, "agentOpen")).held, true);
  assert.equal(view(setMode(idle, "agentOpen")).subtitle, "12 agents are open");
});

test("an agent that finishes holds for the release time", () => {
  const done = setChoice(setChoice(alwaysOn(), "claude", "working"), "claude", "idle");
  const state = setMode(done, "agentWorking");
  assert.equal(view(state).subtitle, "Claude Code finished a moment ago");
  assert.equal(view(later(state, RELEASE_AFTER - 1)).held, true);
  assert.equal(view(later(state, RELEASE_AFTER)).held, false);
  assert.equal(view(later(state, RELEASE_AFTER)).subtitle, "Claude Code is idle");
});

test("always holds with no agent, and the switch ends every hold", () => {
  const always = alwaysOn();
  assert.equal(view(always).held, true);
  assert.equal(view(always).emptyText, "No agent is open");
  assert.equal(view(setEnabled(always, false)).held, false);
  assert.equal(view(setEnabled(always, false)).pose, "off");
  // The invitation shows only when a new agent is all that is missing.
  assert.equal(view(setEnabled(always, false)).emptyText, "No agent is open");
  assert.equal(view(startPause(setMode(always, "agentWorking"), "oneHour")).emptyText, "No agent is open");
  assert.equal(
    view(setMode(always, "agentWorking")).emptyText,
    "Start an agent and Agent Caffeine keeps your Mac awake while it works",
  );
});

test("the safety stop wins over every mode and ends above the floor", () => {
  const low = preset(INITIAL, "low");
  assert.equal(view(low).held, false);
  assert.equal(view(low).pose, "trouble");
  assert.equal(view(low).title, "Agent Caffeine has stopped");
  assert.equal(view(low).subtitle, `The battery is at ${BATTERY_FLOOR}%`);
  assert.equal(view(low).iconLabel, "Agent Caffeine: needs attention");
  // The line of the battery says when it starts again, so no attention line says it a second time.
  assert.equal(view(low).attention, null);
  assert.equal(view(setMode(low, "always")).held, false);
  assert.equal(view(setPower(low, "adapter")).held, true);
  assert.equal(view(setBattery(low, BATTERY_LEVELS[0])).held, true);
  assert.equal(batteryStop(21, true, false), false);
  assert.equal(batteryStop(20, true, false), true);
  assert.equal(batteryStop(24, true, true), true);
  assert.equal(batteryStop(25, true, true), false);
  assert.equal(batteryStop(5, false, true), false);
});

test("a closed lid on battery needs the helper", () => {
  const lid = preset(INITIAL, "lid");
  assert.equal(view(lid).attention, null);
  const without = setLid(setPower(preset(INITIAL, "working"), "battery"), "closed");
  assert.equal(view(without).attention?.kind, "lidClosedNotSetUp");
});

test("durations are said as a person says them", () => {
  assert.equal(lasting(59), null);
  assert.equal(lasting(22 * 60), "for 22 minutes");
  assert.equal(lasting(60 * 60), "for 1 hour");
  assert.equal(lasting(82 * 60 + 30), "for 1 hour 22 minutes");
  assert.equal(lasting(9 * 3600 + 59 * 60), "for 9 hours 59 minutes");
  assert.equal(lasting(13 * 3600 + 20 * 60), "for 13 hours");
  assert.equal(lasting(3 * 86400 + 5), "for 3 days");
  assert.equal(view(preset(INITIAL, "low")).groups[0].detail, "Working for 1 hour 22 minutes");
});

test("a pause holds nothing, names its end and starts again by itself", () => {
  const working = preset(INITIAL, "working");
  const paused = startPause(working, "oneHour");
  const shown = view(paused);
  assert.equal(shown.held, false);
  assert.equal(shown.pose, "paused");
  assert.equal(shown.title, "Agent Caffeine is paused");
  assert.equal(shown.subtitle, "Starts again at 10:41");
  assert.equal(shown.bar.pausedLabel, "Paused until 10:41");
  assert.equal(shown.bar.timer, false);
  assert.equal(shown.iconLabel, "Agent Caffeine: paused");
  // The rows keep their states.
  assert.equal(shown.groups[0].detail, "1 working");
  assert.equal(view(startPause(working, "thirtyMinutes")).subtitle, "Starts again at 10:11");
  assert.equal(view(startPause(working, "untilTomorrow")).subtitle, "Starts again tomorrow at 06:00");
  assert.equal(view(startPause(working, "untilTomorrow")).bar.pausedLabel, "Paused until 06:00");
  assert.equal(view(later(paused, 3599)).held, false);
  assert.equal(view(later(paused, 3600)).held, true);
  assert.equal(view(later(paused, 3600)).bar.pausedLabel, null);
  assert.equal(view(resume(paused)).held, true);
  assert.equal(view(setEnabled(paused, true)).held, true);
  assert.equal(view(setEnabled(paused, false)).pose, "off");
});

test("until tomorrow is 8 hours when the morning is less than 4 hours away", () => {
  // 03:00 at night.
  const night = later(preset(INITIAL, "working"), 17 * 3600 + 19 * 60);
  assert.equal(clockTime(night.now), "03:00");
  assert.equal(view(startPause(night, "untilTomorrow")).subtitle, "Starts again at 11:00");
});

test("stay reachable keeps the Mac awake with no agent at work, until its time", () => {
  const reachable = preset(INITIAL, "reachable");
  const shown = view(reachable);
  assert.equal(shown.held, true);
  assert.equal(shown.pose, "reachable");
  assert.equal(shown.title, "Your Mac stays awake");
  assert.equal(shown.subtitle, "Reachable until 11:41");
  assert.equal(shown.bar.reachableLabel, "Reachable until 11:41");
  assert.equal(shown.bar.timer, false);
  assert.equal(shown.iconLabel, "Agent Caffeine: reachable until 11:41");
  assert.equal(shown.groups[1].detail, "Idle for 1 hour 22 minutes");
  assert.equal(view(later(reachable, 2 * 3600)).held, false);
  assert.equal(view(stopReachable(reachable)).held, false);
  assert.equal(view(setEnabled(reachable, false)).bar.reachableLabel, null);
  assert.equal(view(setEnabled(setEnabled(reachable, false), true)).held, false);
  // An agent that works is named first, and the time stays in the bar.
  const working = setChoice(reachable, "claude", "working");
  assert.equal(view(working).subtitle, "Claude Code is working");
  assert.equal(view(working).bar.reachableLabel, "Reachable until 11:41");
});

test("a pause and stay reachable end each other, and a safety stop ends stay reachable for good", () => {
  const idle = preset(INITIAL, "idle");
  const reachable = startReachable(idle, "fourHours");
  assert.equal(view(reachable).subtitle, "Reachable until 13:41");
  const paused = startPause(reachable, "thirtyMinutes");
  assert.equal(paused.reachableUntil, null);
  assert.equal(view(startReachable(paused, "oneHour")).subtitle, "Reachable until 10:41");
  assert.equal(startReachable(paused, "oneHour").pausedUntil, null);
  const stopped = setBattery(setPower(reachable, "battery"), BATTERY_FLOOR);
  assert.equal(view(stopped).pose, "trouble");
  assert.equal(view(stopped).bar.reachable, false);
  assert.equal(view(setPower(stopped, "adapter")).held, false);
});

test("stay reachable on battery asks for the lid closed helper", () => {
  const reachable = setPower(startReachable(preset(INITIAL, "idle"), "oneHour"), "battery");
  assert.equal(view(reachable).attention?.kind, "reachableNeedsLidClosed");
  assert.equal(view(reachable).bar.reachableCost, "Uses about 1% of battery per hour");
  assert.equal(view(preset(INITIAL, "reachable")).attention, null);
  assert.equal(view(startReachable(preset(INITIAL, "idle"), "oneHour")).bar.reachableCost, null);
});

test("the battery line shows on battery, amber near the floor and red when stopped", () => {
  const onBattery = setPower(preset(INITIAL, "working"), "battery");
  assert.equal(view(preset(INITIAL, "working")).battery, null);
  assert.deepEqual(
    [view(onBattery).battery?.level, view(onBattery).battery?.charge, view(onBattery).battery?.consequence],
    ["normal", "58%", "sleeps at 20%"],
  );
  assert.equal(view(setBattery(onBattery, 31)).battery?.level, "normal");
  assert.equal(view(setBattery(onBattery, 30)).battery?.level, "nearFloor");
  const stopped = view(setBattery(onBattery, BATTERY_FLOOR)).battery;
  assert.deepEqual([stopped?.level, stopped?.charge, stopped?.consequence], ["stopped", null, "starts again at 25%"]);
  assert.equal(stopped?.spoken, "Battery 20 percent, Agent Caffeine starts again at 25 percent");
  assert.equal(view(startPause(onBattery, "oneHour")).battery, null);
  assert.equal(view(setEnabled(onBattery, false)).battery, null);
});

test("the clock ticks while a pause or stay reachable runs with no agent open", () => {
  const empty = setChoice(setChoice(preset(INITIAL, "idle"), "claude", "closed"), "codex", "closed");
  assert.equal(tickEvery(empty), null);
  assert.equal(tickEvery(startReachable(empty, "oneHour")), 1000);
  assert.equal(tickEvery(startPause(empty, "oneHour")), 1000);
  assert.equal(view(empty).clock, "9:41");
});

test("a session that finished says so for a minute, then counts as idle, and the last agent at work is named", () => {
  const done = { state: "idle", command: false, since: 600, before: "working" } as const;
  assert.equal(detailOf(done, 630), "Finished a moment ago");
  assert.equal(detailOf(done, 780), "Idle for 3 minutes");
  assert.equal(headlineText({ kind: "working", subject: { many: 2 } }).subtitle, "2 agents are working");
  assert.equal(headlineText({ kind: "working", subject: { one: "Claude Code" } }).subtitle, "Claude Code is working");
  assert.deepEqual(headlineText({ kind: "idle", subject: { many: 4 } }), { title: "Your Mac can sleep", subtitle: "All agents are idle" });
});

test("the icon in the menu bar is pale while the Mac can sleep, as when off or paused, and each keeps its own label", () => {
  for (const rest of ["asleep", "off", "paused"] as const) {
    assert.deepEqual({ eyes: iconLook(rest).eyes, opacity: iconLook(rest).opacity }, { eyes: "closed", opacity: 0.45 });
  }
  assert.equal(iconLabel(iconLook("asleep")), "Agent Caffeine: your Mac can sleep");
  assert.equal(iconLabel(iconLook("off")), "Agent Caffeine: off");
  assert.equal(iconLabel(iconLook("paused")), "Agent Caffeine: paused");
  assert.equal(iconLook("awake").opacity, 1);
  assert.equal(view(preset(INITIAL, "idle")).iconLabel, "Agent Caffeine: your Mac can sleep");
});
