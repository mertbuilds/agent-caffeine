// @vitest-environment node
// Worker code: Node has the fetch types and Blob.stream() that jsdom lacks.
import { describe, expect, it } from 'vitest';
import { macFileResponse } from './mac-files.ts';
import type { MacFilesBucket } from './mac-files.ts';

const SIZE = 10;
const ETAG = '"etag"';
const DMG = '/mac/agent-caffeine-0.1.0-2.dmg';
const SAVED = 'attachment; filename="agent-caffeine-0.1.0.dmg"';

function metadata(headers: Headers) {
  headers.set('content-type', 'application/x-apple-diskimage');
}

/**
 * A bucket that holds every key but `mac/missing.dmg`, ten bytes each, and
 * leaves the body off when an `If-None-Match` names its etag, as R2 does.
 */
const bucket: MacFilesBucket = {
  get: (key, options) => {
    if (key === 'mac/missing.dmg') {
      return Promise.resolve(null);
    }
    const current = options?.onlyIf.get('if-none-match') === ETAG;
    return Promise.resolve({
      ...(current
        ? {}
        : { body: new Blob([new Uint8Array(options?.range?.length ?? SIZE)]).stream() }),
      httpEtag: ETAG,
      size: SIZE,
      writeHttpMetadata: metadata,
    });
  },
  head: (key) =>
    Promise.resolve(
      key === 'mac/missing.dmg'
        ? null
        : { httpEtag: ETAG, size: SIZE, writeHttpMetadata: metadata },
    ),
};

async function ask(path: string, init?: RequestInit): Promise<Response> {
  const url = new URL(path, 'https://caffeinagent.com');
  const response = await macFileResponse(new Request(url, init), url, bucket);
  if (response === null) {
    throw new Error(`no answer for ${path}`);
  }
  return response;
}

describe('macFileResponse', () => {
  it('saves a dmg under its version, without the build number', async () => {
    const response = await ask(DMG);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-disposition')).toBe(SAVED);
    expect(response.headers.get('content-type')).toBe('application/x-apple-diskimage');
    expect(response.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
    expect(response.headers.get('accept-ranges')).toBe('bytes');
    expect(response.headers.get('content-length')).toBe('10');
  });

  it('answers HEAD and one range with the same name', async () => {
    const head = await ask(DMG, { method: 'HEAD' });
    expect(head.status).toBe(200);
    expect(head.headers.get('content-disposition')).toBe(SAVED);
    expect(head.headers.get('content-length')).toBe('10');

    const range = await ask(DMG, { headers: { range: 'bytes=0-3' } });
    expect(range.status).toBe(206);
    expect(range.headers.get('content-disposition')).toBe(SAVED);
    expect(range.headers.get('content-range')).toBe('bytes 0-3/10');
    expect(range.headers.get('content-length')).toBe('4');
  });

  it('answers a range past the end with 416', async () => {
    const response = await ask(DMG, { headers: { range: 'bytes=10-' } });
    expect(response.status).toBe(416);
    expect(response.headers.get('content-range')).toBe('bytes */10');
  });

  it('answers a cached copy that is still current with 304', async () => {
    const response = await ask(DMG, { headers: { 'if-none-match': ETAG } });
    expect(response.status).toBe(304);
    expect(response.headers.get('etag')).toBe(ETAG);
  });

  it('answers 404 for a file the bucket does not hold, and for any other shape', async () => {
    expect((await ask('/mac/missing.dmg')).status).toBe(404);
    expect((await ask('/mac/missing.dmg', { method: 'HEAD' })).status).toBe(404);
    expect((await ask('/mac/a/b.dmg')).status).toBe(404);
    expect((await ask(`/mac/${'a'.repeat(201)}`)).status).toBe(404);
  });

  it('refuses a method other than GET and HEAD', async () => {
    const response = await ask(DMG, { method: 'POST' });
    expect(response.status).toBe(405);
    expect(response.headers.get('allow')).toBe('GET, HEAD');
  });

  it('serves the feed and latest.json for five minutes, not as attachments', async () => {
    for (const path of ['/mac/appcast.xml', '/mac/latest.json', '/mac/other-0.1.0-2.dmg']) {
      const response = await ask(path);
      expect(response.headers.get('content-disposition'), path).toBeNull();
    }
    expect((await ask('/mac/appcast.xml')).headers.get('cache-control')).toBe(
      'public, max-age=300',
    );
  });

  it('leaves every other path, and the bare /mac/, to the site', async () => {
    for (const path of ['/', '/mac', '/mac/', '/download']) {
      const url = new URL(path, 'https://caffeinagent.com');
      expect(await macFileResponse(new Request(url), url, bucket), path).toBeNull();
    }
  });
});
