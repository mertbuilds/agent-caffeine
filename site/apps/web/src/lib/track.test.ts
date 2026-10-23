// @vitest-environment node
import { afterEach, describe, expect, it } from 'vitest';
import { isLiveHost, rememberedUtm, rememberUtm, track } from './track.ts';

type Call = ReadonlyArray<unknown>;

/** A page on `hostname`, with OpenPanel and a store that note every call. */
function browser(hostname: string): { sent: Array<Call>; stored: Array<Call> } {
  const sent: Array<Call> = [];
  const stored: Array<Call> = [];
  const kept = new Map<string, string>();
  Object.assign(globalThis, {
    sessionStorage: {
      getItem: (key: string) => kept.get(key) ?? null,
      setItem: (key: string, value: string) => {
        stored.push([key, value]);
        kept.set(key, value);
      },
    },
    window: {
      location: { hostname, search: '?utm_source=x' },
      op: (...call: Call) => sent.push(call),
    },
  });
  return { sent, stored };
}

afterEach(() => {
  Reflect.deleteProperty(globalThis, 'window');
  Reflect.deleteProperty(globalThis, 'sessionStorage');
});

describe('track', () => {
  it('counts on the two live hosts only', () => {
    expect(isLiveHost('caffeinagent.com')).toBe(true);
    expect(isLiveHost('www.caffeinagent.com')).toBe(true);
    expect(isLiveHost('caffeinagent.localhost')).toBe(false);
    expect(isLiveHost('localhost')).toBe(false);
    expect(isLiveHost('caffeinagent-web.mertbuilds.workers.dev')).toBe(false);
    expect(isLiveHost('caffeinagent.com.example.org')).toBe(false);
    expect(isLiveHost('evilcaffeinagent.com')).toBe(false);
    expect(isLiveHost('caffeinagent.com.evil.io')).toBe(false);
  });

  it('sends and reads nothing with no window', () => {
    expect(() => track('download_click', { placement: 'hero' })).not.toThrow();
    expect(rememberedUtm()).toBeNull();
  });

  it('sends, keeps and reads nothing on a preview host', () => {
    const { sent, stored } = browser('caffeinagent-web.mertbuilds.workers.dev');
    track('download_click', { placement: 'hero' });
    rememberUtm();
    expect(rememberedUtm()).toBeNull();
    expect(sent).toEqual([]);
    expect(stored).toEqual([]);
  });

  it('sends an event once on the live host', () => {
    const { sent } = browser('caffeinagent.com');
    track('download_click', { placement: 'hero' });
    expect(sent).toEqual([['track', 'download_click', { placement: 'hero' }]]);
  });

  it('keeps the tags of the first page on the live host', () => {
    const { stored } = browser('caffeinagent.com');
    expect(rememberedUtm()).toEqual({ utm_source: 'x' });
    expect(stored).toEqual([['utm', '{"utm_source":"x"}']]);
  });
});
