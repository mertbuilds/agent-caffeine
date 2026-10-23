// @vitest-environment node
import { describe, expect, it } from 'vitest';
import {
  clientIp,
  decideDownload,
  downloadLink,
  downloadUtmFrom,
  hostnameOf,
  isBot,
  isMacBrowser,
  isPrefetch,
  placementFrom,
  trackRequest,
} from './download.ts';
import type { Release } from './release.ts';

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
