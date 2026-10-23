// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { parseLatest, readLatestRelease, type LatestBucket } from './release.ts';

/** A bucket that holds `latest.json` with `text`, or nothing. */
function bucket(text: string | null): LatestBucket {
  return {
    get: () => {
      const body = text === null ? null : new Response(text).body;
      return Promise.resolve(body === null ? null : { body });
    },
  };
}

describe('release', () => {
  it('reads a release and serves its dmg from this site', () => {
    expect(
      parseLatest({
        build: 14,
        filename: 'agent-caffeine-1.0.0.dmg',
        size: 9_491_361,
        url: 'https://files.example.com/mac/agent-caffeine-1.0.0-14.dmg',
        version: '1.0.0',
      }),
    ).toEqual({
      build: '14',
      filename: 'agent-caffeine-1.0.0.dmg',
      href: '/mac/agent-caffeine-1.0.0-14.dmg',
      size: 9_491_361,
      version: '1.0.0',
    });
    expect(parseLatest({ filename: 'a b.dmg', size: 1, version: '1.0.0' })?.href).toBe(
      '/mac/a%20b.dmg',
    );
  });

  it('reads no release from a file without a version, a filename and a size', () => {
    expect(parseLatest(null)).toBeNull();
    expect(parseLatest({ filename: 'a.dmg', size: '1', version: '1.0.0' })).toBeNull();
    expect(parseLatest({ size: 1, version: '1.0.0' })).toBeNull();
  });

  it('has no release without the bucket, before the first release or with a broken file', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    expect(await readLatestRelease(undefined)).toBeNull();
    expect(await readLatestRelease(bucket(null))).toBeNull();
    expect(await readLatestRelease(bucket('{'))).toBeNull();
    expect(await readLatestRelease(bucket('{"version":"1.0.0"}'))).toBeNull();
    expect(
      await readLatestRelease(bucket('{"version":"1.0.0","filename":"a.dmg","size":1}')),
    ).toEqual({ filename: 'a.dmg', href: '/mac/a.dmg', size: 1, version: '1.0.0' });
    vi.restoreAllMocks();
  });
});
