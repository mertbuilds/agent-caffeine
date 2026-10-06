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
  batteryStop,
  clockTime,
  lasting,
  preset,
  resume,
  setBattery,
  setChoice,
  setEnabled,
  setLid,
  setMode,
  setPower,
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
  assert.equal(shown.groups[0].detail, "2 working");
  assert.deepEqual(shown.groups[0].children.map((child) => child.label), ["wiki-6e", "site", "8 idle sessions"]);
  assert.equal(shown.groups[1].detail, "Idle for 6 minutes");
});

test("an agent that waits holds for 5 minutes, then the Mac can sleep", () => {
  const asked = preset(INITIAL, "waiting");
  const first = view(asked);
  assert.equal(first.held, true);
  assert.equal(first.pose, "attentive");
  assert.equal(first.subtitle, "Claude Code is waiting for you, can sleep in 5 minutes");
  assert.equal(first.groups[0].detail, "Asked you a moment ago");
  assert.equal(view(later(asked, WAITING_HOLD - 30)).subtitle, "Claude Code is waiting for you, can sleep in 1 minute");
  const released = view(later(asked, WAITING_HOLD));
  assert.equal(released.held, false);
  assert.equal(released.pose, "asleep");
  assert.equal(released.subtitle, "Claude Code is waiting for your answer");
  assert.equal(released.groups[0].detail, "Waiting for your answer for 5 minutes");
});

test("a busy command holds after the agent is done", () => {
  const shown = view(preset(INITIAL, "build"));
  assert.equal(shown.held, true);
  assert.equal(shown.subtitle, "Claude Code is working");
  assert.equal(shown.groups[0].detail, "Running 1 command for 3 minutes");
  assert.equal(shown.outcome.rest, "a command Claude Code started is still running");
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
});

test("the safety stop wins over every mode and ends above the floor", () => {
  const low = preset(INITIAL, "low");
  assert.equal(view(low).held, false);
  assert.equal(view(low).pose, "trouble");
  assert.equal(view(low).subtitle, `The battery is at ${BATTERY_FLOOR}%`);
  // The line of the battery says when it starts again, so no attention line says it a second time.
  assert.equal(view(low).attention, null);
  assert.equal(view(low).outcome.lead, "Battery at 20%.");
  assert.equal(view(low).outcome.hint, "It starts again at 25%, or on power");
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
  assert.equal(view(lid).outcome.hint, "Lid closed, on battery");
  const without = setLid(setPower(preset(INITIAL, "working"), "battery"), "closed");
  assert.equal(view(without).attention?.kind, "lidClosedNotSetUp");
  assert.equal(view(without).outcome.lead, "Your Mac sleeps:");
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
  assert.equal(shown.title, "agent caffeine is paused");
  assert.equal(shown.subtitle, "Starts again at 10:41");
  assert.equal(shown.bar.pausedLabel, "Paused until 10:41");
  assert.equal(shown.bar.timer, false);
  assert.equal(shown.iconLabel, "agent caffeine, paused");
  // The rows keep their states.
  assert.equal(shown.groups[0].detail, "2 working");
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
  assert.equal(shown.iconLabel, "agent caffeine, reachable until 11:41");
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
    ["normal", "58%", "sleeps below 20%"],
  );
  assert.equal(view(setBattery(onBattery, 31)).battery?.level, "normal");
  assert.equal(view(setBattery(onBattery, 30)).battery?.level, "nearFloor");
  const stopped = view(setBattery(onBattery, BATTERY_FLOOR)).battery;
  assert.deepEqual([stopped?.level, stopped?.charge, stopped?.consequence], ["stopped", "20%", "starts again at 25%"]);
  assert.equal(stopped?.spoken, "Battery 20 percent, agent caffeine starts again at 25 percent");
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
