import type { Utm } from './attribution.ts';
import type { Release } from './latest-release.ts';
import { readLatestRelease } from './latest-release.ts';
import type { MacFilesBucket } from './mac-files.ts';
import { OPENPANEL_API_URL } from './site.ts';
import { isLiveHost } from './track.ts';

/** The address every download link goes to. The server counts the download there, then sends the browser on to the dmg. */
export const DOWNLOAD_PATH = '/download';

const PLACEMENTS = ['header', 'menu', 'hero', 'pricing', 'blog', 'footer'] as const;

export type DownloadPlacement = (typeof PLACEMENTS)[number] | 'other';

/** Where the link sits, from `?from=`. A value that is not on the list counts as "other". */
export function placementFrom(from: string | null): DownloadPlacement {
  return PLACEMENTS.find((placement) => placement === from) ?? 'other';
}

const COUNTED_UTM_KEYS = ['utm_source', 'utm_medium', 'utm_campaign'] as const;

export type DownloadUtm = Partial<Record<(typeof COUNTED_UTM_KEYS)[number], string>>;

const MAX_LENGTH = 100;

/** The three campaign tags the count keeps, each cut at 100 characters. Empty ones are left out. */
export function downloadUtmFrom(params: URLSearchParams): DownloadUtm {
  const utm: DownloadUtm = {};
  for (const key of COUNTED_UTM_KEYS) {
    const value = params.get(key)?.trim().slice(0, MAX_LENGTH);
    if (value) {
      utm[key] = value;
    }
  }
  return utm;
}

/** The link of a download button: where it sits, and the source of the visit when the browser knows one. */
export function downloadLink(placement: string, utm: Utm | null): string {
  const params = new URLSearchParams({ from: placement });
  for (const key of COUNTED_UTM_KEYS) {
    const value = utm?.[key];
    if (value) {
      params.set(key, value);
    }
  }
  return `${DOWNLOAD_PATH}?${params}`;
}

const BOT = /bot|crawler|spider|curl|wget|python-requests|headless|preview|facebookexternalhit/i;

/** True for no user agent and for the programs that fetch links without a person behind them. */
export function isBot(userAgent: string | null): boolean {
  return !userAgent || userAgent.trim() === '' || BOT.test(userAgent);
}

/**
 * True for a browser on a Mac, the only place the dmg runs. Link scanners that follow the link come as
 * Android, iPhone, Windows, Linux or a bare WebKit. Safari on an iPad asks for the desktop site with the
 * user agent of a Mac, so an iPad counts too: the user agent cannot tell the two apart.
 */
export function isMacBrowser(userAgent: string | null): boolean {
  return userAgent !== null && userAgent.includes('Macintosh') && userAgent.includes('Mac OS X');
}

/** True when the browser fetches the link ahead of a click. */
export function isPrefetch(headers: Headers): boolean {
  return ['purpose', 'sec-purpose'].some((name) =>
    headers.get(name)?.toLowerCase().includes('prefetch'),
  );
}

/** The host name of a `host` header, without the port. */
export function hostnameOf(host: string | null): string {
  return (host ?? '').trim().toLowerCase().replace(/:\d+$/, '');
}

/** The visitor's IP address. Cloudflare's own header comes first, then the first hop and the real IP. */
export function clientIp(headers: Headers): string | null {
  const ip =
    headers.get('cf-connecting-ip')?.trim() ||
    headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    headers.get('x-real-ip')?.trim();
  return ip || null;
}

export type DownloadEvent = {
  /** Sent on to OpenPanel for the country and the device. Not kept by this site. */
  ip: string | null;
  name: 'download';
  properties: { build?: string; placement: DownloadPlacement; version: string } & DownloadUtm;
  userAgent: string;
};

export type DownloadDecision = { event: DownloadEvent | null; redirectTo: string };

/**
 * Where a request for the download goes, and the event to count, if any.
 * Every request gets a redirect. Only a person's GET from a browser on a Mac, on the live site, with the secret set, is counted.
 */
export function decideDownload({
  headers,
  host,
  method,
  release,
  search,
  secretSet,
}: {
  headers: Headers;
  host: string | null;
  method: string;
  release: Release | null;
  search: string;
  secretSet: boolean;
}): DownloadDecision {
  if (release === null || !release.href.startsWith('/mac/')) {
    return { event: null, redirectTo: '/' };
  }
  const redirectTo = release.href;
  const userAgent = headers.get('user-agent');
  if (
    !secretSet ||
    method !== 'GET' ||
    !isLiveHost(hostnameOf(host)) ||
    userAgent === null ||
    isBot(userAgent) ||
    !isMacBrowser(userAgent) ||
    isPrefetch(headers)
  ) {
    return { event: null, redirectTo };
  }
  const params = new URLSearchParams(search);
  return {
    event: {
      ip: clientIp(headers),
      name: 'download',
      properties: {
        version: release.version,
        ...(release.build === undefined ? {} : { build: release.build }),
        placement: placementFrom(params.get('from')),
        ...downloadUtmFrom(params),
      },
      userAgent,
    },
    redirectTo,
  };
}

/**
 * The request that counts an event on the server. The secret is what lets a server send one.
 * Without the IP headers OpenPanel takes every server event for one device.
 */
export function trackRequest(
  event: DownloadEvent,
  clientId: string,
  clientSecret: string,
): { init: { body: string; headers: Record<string, string>; method: 'POST' }; url: string } {
  return {
    init: {
      body: JSON.stringify({
        payload: { name: event.name, properties: event.properties },
        type: 'track',
      }),
      headers: {
        'Content-Type': 'application/json',
        'openpanel-client-id': clientId,
        'openpanel-client-secret': clientSecret,
        'user-agent': event.userAgent,
        ...(event.ip === null ? {} : { 'openpanel-client-ip': event.ip, 'x-client-ip': event.ip }),
      },
      method: 'POST',
    },
    url: `${OPENPANEL_API_URL}/track`,
  };
}

/** How long the count may take. The browser has its redirect already; this only bounds the work after it. */
const TRACK_TIMEOUT_MS = 1500;

/** Sends the count to OpenPanel. A failure is logged and never reaches the visitor. */
export async function sendDownloadEvent(
  event: DownloadEvent,
  clientId: string,
  clientSecret: string,
): Promise<void> {
  const { init, url } = trackRequest(event, clientId, clientSecret);
  try {
    const response = await fetch(url, { ...init, signal: AbortSignal.timeout(TRACK_TIMEOUT_MS) });
    if (!response.ok) {
      // oxlint-disable-next-line no-console -- Workers observability keeps the console; a lost count
      console.error(`download: ${url} answered ${response.status}`);
    }
  } catch (error) {
    // oxlint-disable-next-line no-console -- Workers observability keeps the console; a lost count
    console.error(`download: could not reach ${url}`, error);
  }
}

/**
 * Answers `/download` with a 302 to the newest dmg, or to the home page while
 * there is none, never cached, and hands a person's download on a Mac to
 * `count`. `count` is null when the server may not count. `null` for any other path.
 */
export async function downloadRedirect(
  request: Request,
  url: URL,
  bucket: MacFilesBucket,
  count: ((event: DownloadEvent) => void) | null,
): Promise<Response | null> {
  if (url.pathname !== DOWNLOAD_PATH) {
    return null;
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response(null, { headers: { allow: 'GET, HEAD' }, status: 405 });
  }
  const { event, redirectTo } = decideDownload({
    headers: request.headers,
    host: url.host,
    method: request.method,
    release: await readLatestRelease(bucket),
    search: url.search,
    secretSet: count !== null,
  });
  if (event !== null && count !== null) {
    count(event);
  }
  return new Response(null, {
    headers: { 'cache-control': 'no-store', location: redirectTo },
    status: 302,
  });
}
