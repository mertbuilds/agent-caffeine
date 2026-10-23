import { describe, expect, it } from 'vitest';
import { detailOf, headlineText, iconLook, pose } from './simulator.ts';

describe('simulator', () => {
  it('durations are said as a person says them', () => {
    const working = { before: null, command: false, since: 0, state: 'working' } as const;
    expect(detailOf(working, 59)).toBe('Working');
    expect(detailOf(working, 22 * 60)).toBe('Working for 22 minutes');
    expect(detailOf(working, 60 * 60)).toBe('Working for 1 hour');
    expect(detailOf(working, 82 * 60 + 30)).toBe('Working for 1 hour 22 minutes');
    expect(detailOf(working, 9 * 3600 + 59 * 60)).toBe('Working for 9 hours 59 minutes');
    expect(detailOf(working, 13 * 3600 + 20 * 60)).toBe('Working for 13 hours');
    expect(detailOf(working, 3 * 86_400 + 5)).toBe('Working for 3 days');
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

  it('the icon in the menu bar is pale while the Mac can sleep, as when off or paused', () => {
    for (const rest of ['asleep', 'off', 'paused'] as const) {
      expect({ eyes: iconLook(rest).eyes, opacity: iconLook(rest).opacity }).toEqual({
        eyes: 'closed',
        opacity: 0.45,
      });
    }
    expect(iconLook('awake').opacity).toBe(1);
    expect(pose({ kind: 'idle', subject: { many: 3 } })).toBe('asleep');
    expect(pose({ kind: 'finishedRecently', subject: { one: 'Claude Code' } })).toBe('awake');
  });
});
