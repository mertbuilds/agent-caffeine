import { describe, expect, it } from 'vitest';
import { parseLatest } from './latest-release.ts';

const LATEST = {
  build: '2',
  date: '2026-10-23T12:00:00Z',
  filename: 'agent-caffeine-0.1.0.dmg',
  sha256: '0'.repeat(64),
  size: 7_193_211,
  url: 'https://caffeinagent.com/mac/agent-caffeine-0.1.0-2.dmg',
  version: '0.1.0',
};

describe('parseLatest', () => {
  it('reads a latest.json as release.sh writes it, served from this site', () => {
    expect(parseLatest(LATEST)).toEqual({
      build: '2',
      filename: 'agent-caffeine-0.1.0.dmg',
      href: '/mac/agent-caffeine-0.1.0-2.dmg',
      size: 7_193_211,
      version: '0.1.0',
    });
  });

  it('keeps a build given as a number as text', () => {
    expect(parseLatest({ ...LATEST, build: 2 })?.build).toBe('2');
  });

  it('keeps only the path under /mac/ of a url on another host', () => {
    expect(
      parseLatest({
        ...LATEST,
        url: 'https://files.caffeinagent.com/mac/agent-caffeine-0.1.0-2.dmg',
      })?.href,
    ).toBe('/mac/agent-caffeine-0.1.0-2.dmg');
  });

  it('falls back to the filename under /mac/ for a url outside /mac/ or no url at all', () => {
    expect(parseLatest({ ...LATEST, url: 'https://evil.example/x.dmg' })?.href).toBe(
      '/mac/agent-caffeine-0.1.0.dmg',
    );
    expect(parseLatest({ ...LATEST, url: undefined })?.href).toBe('/mac/agent-caffeine-0.1.0.dmg');
    expect(parseLatest({ ...LATEST, url: 'not a url' })?.href).toBe(
      '/mac/agent-caffeine-0.1.0.dmg',
    );
  });

  it('is no release without a version, a filename or a size', () => {
    expect(parseLatest(null)).toBeNull();
    expect(parseLatest('0.1.0')).toBeNull();
    expect(parseLatest({ ...LATEST, version: 1 })).toBeNull();
    expect(parseLatest({ ...LATEST, filename: undefined })).toBeNull();
    expect(parseLatest({ ...LATEST, size: '7 MB' })).toBeNull();
  });
});
