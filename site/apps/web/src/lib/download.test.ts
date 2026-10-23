// @vitest-environment node
// Worker code: Node has the fetch types and Blob.stream() that jsdom lacks.
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  clientIp,
  decideDownload,
  DOWNLOAD_PATH,
  downloadLink,
  downloadRedirect,
  downloadUtmFrom,
  hostnameOf,
  isBot,
  isMacBrowser,
  isPrefetch,
  placementFrom,
  sendDownloadEvent,
  trackRequest,
} from './download.ts';
import type { DownloadEvent } from './download.ts';
import type { Release } from './latest-release.ts';
import type { MacFilesBucket } from './mac-files.ts';

const SAFARI =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const CHROME =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';
const FIREFOX =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0';
/** Safari on an iPad asks for the desktop site, with the user agent of a Mac. */
const IPAD_DESKTOP =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const NOT_A_MAC = [
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko)',
  'Homebrew/4.6.15 (Macintosh; arm64 Mac OS X 15.6.1) curl/8.7.1',
  'curl/8.7.1',
  '',
];

const RELEASE: Release = {
  build: '14',
  filename: 'agent-caffeine-1.0.0.dmg',
  href: '/mac/agent-caffeine-1.0.0-14.dmg',
  size: 9_491_361,
  version: '1.0.0',
};

/** A person's click on the live site, changed by `over`. */
function decide(over: Partial<Parameters<typeof decideDownload>[0]> = {}) {
  return decideDownload({
    headers: new Headers({ 'user-agent': SAFARI, 'x-forwarded-for': '203.0.113.7' }),
    host: 'caffeinagent.com',
    method: 'GET',
    release: RELEASE,
    search: '?from=hero&utm_source=x',
    secretSet: true,
    ...over,
  });
}

describe('download', () => {
  it('keeps a placement on the list and counts any other as other', () => {
    for (const placement of ['header', 'menu', 'hero', 'pricing', 'blog', 'footer']) {
      expect(placementFrom(placement)).toBe(placement);
    }
    expect(placementFrom(null)).toBe('other');
    expect(placementFrom('')).toBe('other');
    expect(placementFrom('Hero')).toBe('other');
    expect(placementFrom('<script>')).toBe('other');
  });

  it('keeps only three tags, each cut at 100 characters', () => {
    const params = new URLSearchParams(
      `utm_source=${'a'.repeat(300)}&utm_medium=ad&utm_campaign=%20&utm_term=x&utm_content=y&email=a%40b.c`,
    );
    expect(downloadUtmFrom(params)).toEqual({ utm_medium: 'ad', utm_source: 'a'.repeat(100) });
    expect(downloadUtmFrom(new URLSearchParams(''))).toEqual({});
  });

  it('names the place of a download link, and the source when there is one', () => {
    expect(downloadLink('hero', null)).toBe('/download?from=hero');
    expect(downloadLink('footer', {})).toBe('/download?from=footer');
    expect(
      downloadLink('pricing', {
        utm_campaign: 'launch week',
        utm_source: 'claudemarketplaces',
        utm_term: 'x',
      }),
    ).toBe('/download?from=pricing&utm_source=claudemarketplaces&utm_campaign=launch+week');
  });

  it('takes no user agent and the known fetchers for bots', () => {
    expect(isBot(null)).toBe(true);
    expect(isBot('')).toBe(true);
    expect(isBot('  ')).toBe(true);
    for (const userAgent of [
      'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
      'curl/8.7.1',
      'Wget/1.21',
      'python-requests/2.32',
      'Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/126.0',
      'facebookexternalhit/1.1',
      'Slackbot-LinkExpanding 1.0',
      'Twitterbot/1.0',
      'LinkedInBot/1.0',
      'Mozilla/5.0 (compatible; Discordbot/2.0)',
      'Google-PageRenderer Google (+https://developers.google.com/+/web/snippet/) preview',
      'SomeCrawler/1.0',
      'Baiduspider/2.0',
    ]) {
      expect(isBot(userAgent), userAgent).toBe(true);
    }
    expect(isBot(SAFARI)).toBe(false);
  });

  it('sees a prefetch in either header', () => {
    expect(isPrefetch(new Headers({ purpose: 'prefetch' }))).toBe(true);
    expect(isPrefetch(new Headers({ 'sec-purpose': 'prefetch;prerender' }))).toBe(true);
    expect(isPrefetch(new Headers({ 'Sec-Purpose': 'Prefetch' }))).toBe(true);
    expect(isPrefetch(new Headers({ 'user-agent': SAFARI }))).toBe(false);
  });

  it('takes the port off a host header', () => {
    expect(hostnameOf('caffeinagent.com')).toBe('caffeinagent.com');
    expect(hostnameOf('Caffeinagent.com:443')).toBe('caffeinagent.com');
    expect(hostnameOf('localhost:3000')).toBe('localhost');
    expect(hostnameOf(null)).toBe('');
  });

  it("takes the visitor's address from Cloudflare, then the first hop, then the real IP", () => {
    expect(
      clientIp(
        new Headers({
          'cf-connecting-ip': '203.0.113.7',
          'x-forwarded-for': '198.51.100.1',
          'x-real-ip': '198.51.100.2',
        }),
      ),
    ).toBe('203.0.113.7');
    expect(
      clientIp(
        new Headers({ 'x-forwarded-for': ' 203.0.113.7 , 10.0.0.1', 'x-real-ip': '198.51.100.2' }),
      ),
    ).toBe('203.0.113.7');
    expect(clientIp(new Headers({ 'x-real-ip': '198.51.100.2' }))).toBe('198.51.100.2');
    expect(clientIp(new Headers({ 'x-forwarded-for': '' }))).toBeNull();
    expect(clientIp(new Headers())).toBeNull();
  });

  it("counts a person's click on the live site and sends it to the dmg", () => {
    expect(decide()).toEqual({
      event: {
        ip: '203.0.113.7',
        name: 'download',
        properties: { build: '14', placement: 'hero', utm_source: 'x', version: '1.0.0' },
        userAgent: SAFARI,
      },
      redirectTo: '/mac/agent-caffeine-1.0.0-14.dmg',
    });
    expect(decide({ host: 'www.caffeinagent.com:443' }).event?.name).toBe('download');
    expect(decide({ search: '' }).event?.properties.placement).toBe('other');
  });

  it('counts a release with no build number without one', () => {
    const { build: _build, ...release } = RELEASE;
    expect(decide({ release }).event?.properties).toEqual({
      placement: 'hero',
      utm_source: 'x',
      version: '1.0.0',
    });
  });

  it('sends the request to the dmg and counts nothing off the live site', () => {
    for (const host of [
      'caffeinagent.local',
      'localhost:3000',
      'x.workers.dev',
      'caffeinagent.com.evil.io',
      null,
    ]) {
      expect(decide({ host })).toEqual({ event: null, redirectTo: RELEASE.href });
    }
  });

  it('counts nothing without the secret', () => {
    expect(decide({ secretSet: false })).toEqual({ event: null, redirectTo: RELEASE.href });
  });

  it('redirects a HEAD, a bot and a prefetch and counts none of them', () => {
    const expected = { event: null, redirectTo: RELEASE.href };
    expect(decide({ method: 'HEAD' })).toEqual(expected);
    expect(decide({ headers: new Headers() })).toEqual(expected);
    expect(decide({ headers: new Headers({ 'user-agent': 'curl/8.7.1' }) })).toEqual(expected);
    expect(
      decide({ headers: new Headers({ 'sec-purpose': 'prefetch', 'user-agent': SAFARI }) }),
    ).toEqual(expected);
  });

  it('takes only a browser on a Mac for a Mac browser', () => {
    for (const userAgent of [SAFARI, CHROME, FIREFOX, IPAD_DESKTOP]) {
      expect(isMacBrowser(userAgent), userAgent).toBe(true);
    }
    for (const userAgent of NOT_A_MAC.filter((entry) => !entry.startsWith('Homebrew'))) {
      expect(isMacBrowser(userAgent), userAgent).toBe(false);
    }
    expect(isMacBrowser(null)).toBe(false);
  });

  it('counts Safari, Chrome and Firefox on a Mac, and an iPad that asks for the desktop site with them', () => {
    for (const userAgent of [SAFARI, CHROME, FIREFOX, IPAD_DESKTOP]) {
      expect(
        decide({ headers: new Headers({ 'user-agent': userAgent }) }).event?.userAgent,
        userAgent,
      ).toBe(userAgent);
    }
  });

  it('redirects a phone, a tablet, Windows, Linux, a bare WebKit, Homebrew, curl and no user agent and counts none', () => {
    for (const userAgent of NOT_A_MAC) {
      expect(decide({ headers: new Headers({ 'user-agent': userAgent }) }), userAgent).toEqual({
        event: null,
        redirectTo: RELEASE.href,
      });
    }
  });

  it('sends the request to the home page with no release, or a release with no file', () => {
    expect(decide({ release: null })).toEqual({ event: null, redirectTo: '/' });
    expect(decide({ release: { ...RELEASE, href: '#' } })).toEqual({
      event: null,
      redirectTo: '/',
    });
  });

  it("sends the count to OpenPanel with the secret and the visitor's address and browser", () => {
    const { event } = decide();
    expect(event).not.toBeNull();
    if (event === null) {
      return;
    }
    const { init, url } = trackRequest(event, 'client-id', 'client-secret');
    expect(url).toBe('https://analytics.vinena.studio/api/track');
    expect(init.method).toBe('POST');
    expect(init.headers).toEqual({
      'Content-Type': 'application/json',
      'openpanel-client-id': 'client-id',
      'openpanel-client-ip': '203.0.113.7',
      'openpanel-client-secret': 'client-secret',
      'user-agent': SAFARI,
      'x-client-ip': '203.0.113.7',
    });
    expect(JSON.parse(init.body)).toEqual({
      payload: {
        name: 'download',
        properties: { build: '14', placement: 'hero', utm_source: 'x', version: '1.0.0' },
      },
      type: 'track',
    });
  });

  it('sends no IP header with no address', () => {
    const { event } = decide({ headers: new Headers({ 'user-agent': SAFARI }) });
    expect(event).not.toBeNull();
    if (event === null) {
      return;
    }
    const { headers } = trackRequest(event, 'client-id', 'client-secret').init;
    expect('openpanel-client-ip' in headers).toBe(false);
    expect('x-client-ip' in headers).toBe(false);
  });
});

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

async function ask(
  bucket: MacFilesBucket,
  init?: RequestInit,
  path = '/download',
  count: ((event: DownloadEvent) => void) | null = null,
) {
  const url = new URL(path, 'https://caffeinagent.com');
  return downloadRedirect(new Request(url, init), url, bucket, count);
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('downloadRedirect', () => {
  it('is the route every download button links to', () => {
    expect(DOWNLOAD_PATH).toBe('/download');
  });

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

  it("hands a person's GET on a Mac to the count, and no HEAD, bot or other system", async () => {
    const counted: Array<DownloadEvent> = [];
    const count = (event: DownloadEvent) => counted.push(event);
    const get = { headers: { 'user-agent': SAFARI } };
    await ask(bucketWith(LATEST), get, '/download?from=pricing', count);
    await ask(bucketWith(LATEST), { ...get, method: 'HEAD' }, '/download', count);
    await ask(bucketWith(LATEST), { headers: { 'user-agent': 'curl/8.7.1' } }, '/download', count);
    await ask(bucketWith(LATEST), { headers: { 'user-agent': NOT_A_MAC[3] ?? '' } }, '/download', count);
    expect(counted.map((event) => event.properties)).toEqual([
      { build: '2', placement: 'pricing', version: '0.1.0' },
    ]);
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

describe('sendDownloadEvent', () => {
  const event: DownloadEvent = {
    ip: null,
    name: 'download',
    properties: { placement: 'hero', version: '1.0.0' },
    userAgent: SAFARI,
  };

  it('posts the count to OpenPanel with a timeout', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null));
    await sendDownloadEvent(event, 'client-id', 'client-secret');
    const [url, init] = fetchMock.mock.calls[0] ?? [];
    expect(url).toBe('https://analytics.vinena.studio/api/track');
    expect(init?.method).toBe('POST');
    expect(init?.signal).toBeInstanceOf(AbortSignal);
  });

  it('logs a refused or failed count and never throws', async () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
      .mockRejectedValueOnce(new Error('offline'));
    await sendDownloadEvent(event, 'client-id', 'client-secret');
    await sendDownloadEvent(event, 'client-id', 'client-secret');
    expect(String(error.mock.calls[0]?.[0])).toMatch(/answered 401/u);
    expect(String(error.mock.calls[1]?.[0])).toMatch(/could not reach/u);
  });
});
