import { describe, expect, it } from 'vitest';
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
} from './simulator.ts';

/** Moves the clock on by simulated seconds. */
function later(state: SimState, seconds: number): SimState {
  return advance(state, (seconds * 1000) / SPEED);
}

/** The mode "always" with no agent open. */
function alwaysOn(): SimState {
  return setMode(
    setChoice(setChoice(preset(INITIAL, 'idle'), 'claude', 'closed'), 'codex', 'closed'),
    'always',
  );
}

describe('simulator', () => {
  it('working sessions keep the Mac awake, idle ones are only counted', () => {
    const shown = view(preset(INITIAL, 'working'));
    expect(shown.held).toBe(true);
    expect(shown.pose).toBe('awake');
    expect(shown.subtitle).toBe('2 agents are working');
    // Two different agents work, so the count of the headline is the count the reader sees.
    expect(shown.groups.map((group) => group.title)).toEqual(['Claude Code', 'Codex · website']);
    expect(shown.groups[0]?.detail).toBe('1 working');
    expect(shown.groups[0]?.children.map((child) => child.label)).toEqual([
      'wiki-6e',
      '8 idle sessions',
    ]);
    expect(shown.groups[1]?.detail).toBe('Working for 3 minutes');
  });

  it('a wait begins when it is set, whatever the clock did before', () => {
    const quit = setChoice(
      setChoice(preset(INITIAL, 'working'), 'claude', 'closed'),
      'codex',
      'closed',
    );
    const asked = setChoice(later(quit, 3600), 'claude', 'waiting');
    expect(view(asked).held).toBe(true);
    expect(view(asked).subtitle).toBe(
      'Claude Code is waiting for you, for at least 5 more minutes',
    );
    expect(view(asked).groups[0]?.detail).toBe('Waiting for your answer');
    // A wait that ran out begins again when it is set again.
    const released = later(asked, WAITING_HOLD + 300);
    expect(view(released).held).toBe(false);
    expect(view(released).groups[0]?.detail).toBe('Waiting for your answer for 10 minutes');
    const again = setChoice(released, 'claude', 'waiting');
    expect(view(again).held).toBe(true);
    expect(view(again).subtitle).toBe(
      'Claude Code is waiting for you, for at least 5 more minutes',
    );
    // A wait that still holds is left alone.
    expect(setChoice(asked, 'claude', 'waiting')).toBe(asked);
  });

  it('an agent that waits holds for 5 minutes, then the Mac can sleep', () => {
    const asked = preset(INITIAL, 'waiting');
    const first = view(asked);
    expect(first.held).toBe(true);
    expect(first.pose).toBe('attentive');
    expect(first.subtitle).toBe('Claude Code is waiting for you, for at least 5 more minutes');
    expect(first.groups[0]?.detail).toBe('Asked you a moment ago');
    expect(view(later(asked, WAITING_HOLD - 30)).subtitle).toBe(
      'Claude Code is waiting for you, for at least 1 more minute',
    );
    const released = view(later(asked, WAITING_HOLD));
    expect(released.held).toBe(false);
    expect(released.pose).toBe('asleep');
    expect(released.subtitle).toBe('Claude Code is waiting for you');
    expect(released.groups[0]?.detail).toBe('Waiting for your answer for 5 minutes');
  });

  it('the menu says what Agent Caffeine does, and when the Mac sleeps only with the lid closed on battery', () => {
    const asked = preset(INITIAL, 'waiting');
    expect(sleepOutlook(asked)).toEqual({ after: WAITING_HOLD, kind: 'letsGo' });
    expect(sleepOutlookText(sleepOutlook(asked))).toBe(
      'Agent Caffeine keeps your Mac awake for 5 more minutes',
    );
    // Only the helper keeps the Mac awake with the lid closed on battery.
    const closed = setLid(allowHelper(setPower(asked, 'battery')), 'closed');
    expect(view(closed).subtitle).toBe(
      'Claude Code is waiting for you, your Mac sleeps in 5 minutes',
    );
    expect(sleepOutlookText(sleepOutlook(closed))).toBe('Your Mac sleeps in 5 minutes');
    expect(view(setPower(closed, 'adapter')).subtitle).toBe(
      'Claude Code is waiting for you, for at least 5 more minutes',
    );
    // Another agent works, so nothing is said about sleep.
    const busy = setChoice(asked, 'codex', 'working');
    expect(view(busy).subtitle).toBe('Codex is working');
    expect(sleepOutlookText(sleepOutlook(busy))).toBe(null);
    // The Mac stays awake anyway in the mode "while an agent is open".
    expect(view(setMode(asked, 'agentOpen')).subtitle).toBe('Claude Code is waiting for you');
    expect(sleepOutlookText(sleepOutlook(later(asked, WAITING_HOLD)))).toBe(null);
  });

  it('a busy command holds after the agent is done', () => {
    const shown = view(preset(INITIAL, 'build'));
    expect(shown.held).toBe(true);
    expect(shown.subtitle).toBe('Claude Code is working');
    expect(shown.groups[0]?.detail).toBe('Running 1 command for 3 minutes');
  });

  it('idle sessions never hold while the mode is working, and hold while it is open', () => {
    const idle = preset(INITIAL, 'idle');
    expect(view(idle).held).toBe(false);
    expect(view(idle).subtitle).toBe('All agents are idle');
    expect(view(idle).groups.map((group) => group.detail)).toEqual([
      '2 idle sessions',
      '10 idle sessions',
    ]);
    expect(view(setMode(idle, 'agentOpen')).held).toBe(true);
    expect(view(setMode(idle, 'agentOpen')).subtitle).toBe('12 agents are open');
  });

  it('an agent that finishes holds for the release time', () => {
    const done = setChoice(setChoice(alwaysOn(), 'claude', 'working'), 'claude', 'idle');
    const state = setMode(done, 'agentWorking');
    expect(view(state).subtitle).toBe('Claude Code finished a moment ago');
    expect(view(later(state, RELEASE_AFTER - 1)).held).toBe(true);
    expect(view(later(state, RELEASE_AFTER)).held).toBe(false);
    expect(view(later(state, RELEASE_AFTER)).subtitle).toBe('Claude Code is idle');
  });

  it('always holds with no agent, and the switch ends every hold', () => {
    const always = alwaysOn();
    expect(view(always).held).toBe(true);
    expect(view(always).emptyText).toBe('No agent is open');
    expect(view(setEnabled(always, false)).held).toBe(false);
    expect(view(setEnabled(always, false)).pose).toBe('off');
    // The invitation shows only when a new agent is all that is missing.
    expect(view(setEnabled(always, false)).emptyText).toBe('No agent is open');
    expect(view(startPause(setMode(always, 'agentWorking'), 'oneHour')).emptyText).toBe(
      'No agent is open',
    );
    expect(view(setMode(always, 'agentWorking')).emptyText).toBe(
      'Start an agent and Agent Caffeine keeps your Mac awake while it works',
    );
  });

  it('the safety stop wins over every mode and ends above the floor', () => {
    const low = preset(INITIAL, 'low');
    expect(view(low).held).toBe(false);
    expect(view(low).pose).toBe('trouble');
    expect(view(low).title).toBe('Agent Caffeine has stopped');
    expect(view(low).subtitle).toBe(`The battery is at ${BATTERY_FLOOR}%`);
    expect(view(low).iconLabel).toBe('Agent Caffeine: needs attention');
    // The line of the battery says when it starts again, so no attention line says it a second time.
    expect(view(low).attention).toBe(null);
    expect(view(setMode(low, 'always')).held).toBe(false);
    expect(view(setPower(low, 'adapter')).held).toBe(true);
    expect(view(setBattery(low, BATTERY_LEVELS[0])).held).toBe(true);
    expect(batteryStop(21, true, false)).toBe(false);
    expect(batteryStop(20, true, false)).toBe(true);
    expect(batteryStop(24, true, true)).toBe(true);
    expect(batteryStop(25, true, true)).toBe(false);
    expect(batteryStop(5, false, true)).toBe(false);
  });

  it('a closed lid on battery needs the helper', () => {
    const lid = preset(INITIAL, 'lid');
    expect(view(lid).attention).toBe(null);
    const without = setLid(setPower(preset(INITIAL, 'working'), 'battery'), 'closed');
    expect(view(without).attention?.kind).toBe('lidClosedNotSetUp');
  });

  it('durations are said as a person says them', () => {
    expect(lasting(59)).toBe(null);
    expect(lasting(22 * 60)).toBe('for 22 minutes');
    expect(lasting(60 * 60)).toBe('for 1 hour');
    expect(lasting(82 * 60 + 30)).toBe('for 1 hour 22 minutes');
    expect(lasting(9 * 3600 + 59 * 60)).toBe('for 9 hours 59 minutes');
    expect(lasting(13 * 3600 + 20 * 60)).toBe('for 13 hours');
    expect(lasting(3 * 86_400 + 5)).toBe('for 3 days');
    expect(view(preset(INITIAL, 'low')).groups[0]?.detail).toBe('Working for 1 hour 22 minutes');
  });

  it('a pause holds nothing, names its end and starts again by itself', () => {
    const working = preset(INITIAL, 'working');
    const paused = startPause(working, 'oneHour');
    const shown = view(paused);
    expect(shown.held).toBe(false);
    expect(shown.pose).toBe('paused');
    expect(shown.title).toBe('Agent Caffeine is paused');
    expect(shown.subtitle).toBe('Starts again at 10:41');
    expect(shown.bar.pausedLabel).toBe('Paused until 10:41');
    expect(shown.bar.timer).toBe(false);
    expect(shown.iconLabel).toBe('Agent Caffeine: paused');
    // The rows keep their states.
    expect(shown.groups[0]?.detail).toBe('1 working');
    expect(view(startPause(working, 'thirtyMinutes')).subtitle).toBe('Starts again at 10:11');
    expect(view(startPause(working, 'untilTomorrow')).subtitle).toBe(
      'Starts again tomorrow at 06:00',
    );
    expect(view(startPause(working, 'untilTomorrow')).bar.pausedLabel).toBe('Paused until 06:00');
    expect(view(later(paused, 3599)).held).toBe(false);
    expect(view(later(paused, 3600)).held).toBe(true);
    expect(view(later(paused, 3600)).bar.pausedLabel).toBe(null);
    expect(view(resume(paused)).held).toBe(true);
    expect(view(setEnabled(paused, true)).held).toBe(true);
    expect(view(setEnabled(paused, false)).pose).toBe('off');
  });

  it('until tomorrow is 8 hours when the morning is less than 4 hours away', () => {
    // 03:00 at night.
    const night = later(preset(INITIAL, 'working'), 17 * 3600 + 19 * 60);
    expect(clockTime(night.now)).toBe('03:00');
    expect(view(startPause(night, 'untilTomorrow')).subtitle).toBe('Starts again at 11:00');
  });

  it('stay reachable keeps the Mac awake with no agent at work, until its time', () => {
    const reachable = preset(INITIAL, 'reachable');
    const shown = view(reachable);
    expect(shown.held).toBe(true);
    expect(shown.pose).toBe('reachable');
    expect(shown.title).toBe('Your Mac stays awake');
    expect(shown.subtitle).toBe('Reachable until 11:41');
    expect(shown.bar.reachableLabel).toBe('Reachable until 11:41');
    expect(shown.bar.timer).toBe(false);
    expect(shown.iconLabel).toBe('Agent Caffeine: reachable until 11:41');
    expect(shown.groups[1]?.detail).toBe('Idle for 1 hour 22 minutes');
    expect(view(later(reachable, 2 * 3600)).held).toBe(false);
    expect(view(stopReachable(reachable)).held).toBe(false);
    expect(view(setEnabled(reachable, false)).bar.reachableLabel).toBe(null);
    expect(view(setEnabled(setEnabled(reachable, false), true)).held).toBe(false);
    // An agent that works is named first, and the time stays in the bar.
    const working = setChoice(reachable, 'claude', 'working');
    expect(view(working).subtitle).toBe('Claude Code is working');
    expect(view(working).bar.reachableLabel).toBe('Reachable until 11:41');
  });

  it('a pause and stay reachable end each other, and a safety stop ends stay reachable for good', () => {
    const idle = preset(INITIAL, 'idle');
    const reachable = startReachable(idle, 'fourHours');
    expect(view(reachable).subtitle).toBe('Reachable until 13:41');
    const paused = startPause(reachable, 'thirtyMinutes');
    expect(paused.reachableUntil).toBe(null);
    expect(view(startReachable(paused, 'oneHour')).subtitle).toBe('Reachable until 10:41');
    expect(startReachable(paused, 'oneHour').pausedUntil).toBe(null);
    const stopped = setBattery(setPower(reachable, 'battery'), BATTERY_FLOOR);
    expect(view(stopped).pose).toBe('trouble');
    expect(view(stopped).bar.reachable).toBe(false);
    expect(view(setPower(stopped, 'adapter')).held).toBe(false);
  });

  it('stay reachable on battery asks for the lid closed helper', () => {
    const reachable = setPower(startReachable(preset(INITIAL, 'idle'), 'oneHour'), 'battery');
    expect(view(reachable).attention?.kind).toBe('reachableNeedsLidClosed');
    expect(view(reachable).bar.reachableCost).toBe('Uses about 1% of battery per hour');
    expect(view(preset(INITIAL, 'reachable')).attention).toBe(null);
    expect(view(startReachable(preset(INITIAL, 'idle'), 'oneHour')).bar.reachableCost).toBe(null);
  });

  it('the battery line shows on battery, amber near the floor and red when stopped', () => {
    const onBattery = setPower(preset(INITIAL, 'working'), 'battery');
    expect(view(preset(INITIAL, 'working')).battery).toBe(null);
    expect([
      view(onBattery).battery?.level,
      view(onBattery).battery?.charge,
      view(onBattery).battery?.consequence,
    ]).toEqual(['normal', '58%', 'sleeps at 20%']);
    expect(view(setBattery(onBattery, 31)).battery?.level).toBe('normal');
    expect(view(setBattery(onBattery, 30)).battery?.level).toBe('nearFloor');
    const stopped = view(setBattery(onBattery, BATTERY_FLOOR)).battery;
    expect([stopped?.level, stopped?.charge, stopped?.consequence]).toEqual([
      'stopped',
      null,
      'starts again at 25%',
    ]);
    expect(stopped?.spoken).toBe('Battery 20 percent, Agent Caffeine starts again at 25 percent');
    expect(view(startPause(onBattery, 'oneHour')).battery).toBe(null);
    expect(view(setEnabled(onBattery, false)).battery).toBe(null);
  });

  it('the clock ticks while a pause or stay reachable runs with no agent open', () => {
    const empty = setChoice(
      setChoice(preset(INITIAL, 'idle'), 'claude', 'closed'),
      'codex',
      'closed',
    );
    expect(tickEvery(empty)).toBe(null);
    expect(tickEvery(startReachable(empty, 'oneHour'))).toBe(1000);
    expect(tickEvery(startPause(empty, 'oneHour'))).toBe(1000);
    expect(view(empty).clock).toBe('9:41');
  });

  it('a session that finished says so for a minute, then counts as idle, and the last agent at work is named', () => {
    const done = { before: 'working', command: false, since: 600, state: 'idle' } as const;
    expect(detailOf(done, 630)).toBe('Finished a moment ago');
    expect(detailOf(done, 780)).toBe('Idle for 3 minutes');
    expect(headlineText({ kind: 'working', subject: { many: 2 } }).subtitle).toBe(
      '2 agents are working',
    );
    expect(headlineText({ kind: 'working', subject: { one: 'Claude Code' } }).subtitle).toBe(
      'Claude Code is working',
    );
    expect(headlineText({ kind: 'idle', subject: { many: 4 } })).toEqual({
      subtitle: 'All agents are idle',
      title: 'Your Mac can sleep',
    });
  });

  it('the icon in the menu bar is pale while the Mac can sleep, as when off or paused, and each keeps its own label', () => {
    for (const rest of ['asleep', 'off', 'paused'] as const) {
      expect({ eyes: iconLook(rest).eyes, opacity: iconLook(rest).opacity }).toEqual({
        eyes: 'closed',
        opacity: 0.45,
      });
    }
    expect(iconLabel(iconLook('asleep'))).toBe('Agent Caffeine: your Mac can sleep');
    expect(iconLabel(iconLook('off'))).toBe('Agent Caffeine: off');
    expect(iconLabel(iconLook('paused'))).toBe('Agent Caffeine: paused');
    expect(iconLook('awake').opacity).toBe(1);
    expect(view(preset(INITIAL, 'idle')).iconLabel).toBe('Agent Caffeine: your Mac can sleep');
  });
});
