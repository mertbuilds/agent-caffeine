// @vitest-environment node
// Worker code: Node has the fetch types and Blob.stream() that jsdom lacks.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DOWNLOAD_PATH, downloadRedirect, downloadTarget } from './download.ts';
import type { Release } from './latest-release.ts';
import type { MacFilesBucket } from './mac-files.ts';

const RELEASE: Release = {
  build: '2',
  filename: 'agent-caffeine-0.1.0.dmg',
  href: '/mac/agent-caffeine-0.1.0-2.dmg',
  size: 7_193_211,
  version: '0.1.0',
};

const LATEST = JSON.stringify({
  build: '2',
  filename: 'agent-caffeine-0.1.0.dmg',
  size: 7_193_211,
  url: 'https://caffeinagent.com/mac/agent-caffeine-0.1.0-2.dmg',
  version: '0.1.0',
});

function file(text: string) {
  return {
    body: new Blob([text]).stream(),
    httpEtag: '"etag"',
    size: text.length,
    writeHttpMetadata: () => {},
  };
}

/** A bucket whose `mac/latest.json` holds `body`, or none when `body` is null. */
function bucketWith(body: string | null, asked: Array<string> = []): MacFilesBucket {
  return {
    get: (key) => {
      asked.push(key);
      return Promise.resolve(body === null ? null : file(body));
    },
    head: () => Promise.resolve(null),
  };
}

async function ask(bucket: MacFilesBucket, init?: RequestInit, path = '/download') {
  const url = new URL(path, 'https://caffeinagent.com');
  return downloadRedirect(new Request(url, init), url, bucket);
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('downloadTarget', () => {
  it('is the route every download button links to', () => {
    expect(DOWNLOAD_PATH).toBe('/download');
  });

  it('is the dmg on this site', () => {
    expect(downloadTarget(RELEASE)).toBe('/mac/agent-caffeine-0.1.0-2.dmg');
  });

  it('is home before the first release, or for a link off /mac/', () => {
    expect(downloadTarget(null)).toBe('/');
    expect(downloadTarget({ ...RELEASE, href: '#' })).toBe('/');
    expect(downloadTarget({ ...RELEASE, href: 'https://evil.example/x.dmg' })).toBe('/');
  });
});

describe('downloadRedirect', () => {
  it('sends GET and HEAD to the newest dmg, never cached', async () => {
    const asked: Array<string> = [];
    for (const method of ['GET', 'HEAD']) {
      const response = await ask(bucketWith(LATEST, asked), { method });
      expect(response?.status, method).toBe(302);
      expect(response?.headers.get('location'), method).toBe('/mac/agent-caffeine-0.1.0-2.dmg');
      expect(response?.headers.get('cache-control'), method).toBe('no-store');
    }
    expect(asked).toEqual(['mac/latest.json', 'mac/latest.json']);
  });

  it('sends the browser home while the bucket holds no latest.json', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const response = await ask(bucketWith(null));
    expect(response?.status).toBe(302);
    expect(response?.headers.get('location')).toBe('/');
    expect(error).not.toHaveBeenCalled();
  });

  it('sends the browser home, and logs why, for a latest.json that is broken', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    expect((await ask(bucketWith('<html>')))?.headers.get('location')).toBe('/');
    expect(String(error.mock.calls[0]?.[0])).toMatch(/could not be read/u);
    expect((await ask(bucketWith('{"version":1}')))?.headers.get('location')).toBe('/');
    expect(String(error.mock.calls[1]?.[0])).toMatch(/needs a version/u);
  });

  it('sends the browser home, and logs why, when the bucket fails', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    const failing: MacFilesBucket = {
      get: () => Promise.reject(new Error('R2 down')),
      head: () => Promise.resolve(null),
    };
    expect((await ask(failing))?.headers.get('location')).toBe('/');
    expect(error).toHaveBeenCalledOnce();
  });

  it('refuses another method, and leaves every other path to the site', async () => {
    const refused = await ask(bucketWith(LATEST), { method: 'POST' });
    expect(refused?.status).toBe(405);
    expect(refused?.headers.get('allow')).toBe('GET, HEAD');
    for (const path of ['/', '/download/', '/downloads', '/mac/latest.json']) {
      expect(await ask(bucketWith(LATEST), undefined, path), path).toBeNull();
    }
  });
});
