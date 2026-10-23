import { createServerFn } from '@tanstack/react-start';

/** The newest release, as `latest.json` names it. */
export interface Release {
  /** The build number, when `latest.json` gives one. */
  build?: string;
  /** The name the browser saves the dmg under. */
  filename: string;
  /** The path of the dmg on this site, under `/mac/`. */
  href: string;
  size: number;
  version: string;
}

/** The key of the file the release script writes after the dmg for every release. */
const LATEST_KEY = 'mac/latest.json';

/** The slice of the `MAC_FILES` R2 binding read here: one file by its key. */
export type LatestBucket = {
  get(key: string): Promise<{ body?: ReadableStream } | null>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isBucket(value: unknown): value is LatestBucket {
  return isRecord(value) && typeof value['get'] === 'function';
}

function hrefFor(url: unknown, filename: string): string {
  if (typeof url === 'string' && URL.canParse(url)) {
    const path = new URL(url).pathname;
    if (path.startsWith('/mac/')) {
      return path;
    }
  }
  return `/mac/${encodeURIComponent(filename)}`;
}

/**
 * The release in a `latest.json`, or null when the file does not hold a
 * version and a filename as text and a size as a number. The dmg is always
 * served from this site under `/mac/`, whatever host the file names.
 */
export function parseLatest(data: unknown): Release | null {
  const { build, filename, size, url, version } = isRecord(data) ? data : {};
  if (typeof version !== 'string' || typeof filename !== 'string' || typeof size !== 'number') {
    return null;
  }
  return {
    ...(typeof build === 'string' || typeof build === 'number' ? { build: String(build) } : {}),
    filename,
    href: hrefFor(url, filename),
    size,
    version,
  };
}

/**
 * The newest release from the bucket's `latest.json`. Null without the
 * bucket, before the first release, and when the file cannot be read or holds
 * no release, so the page never links to a download that is not there.
 */
export async function readLatestRelease(bucket: LatestBucket | undefined): Promise<Release | null> {
  if (bucket === undefined) {
    return null;
  }
  try {
    const file = await bucket.get(LATEST_KEY);
    if (file === null || file.body === undefined) {
      return null;
    }
    const release = parseLatest(await new Response(file.body).json());
    if (release === null) {
      // oxlint-disable-next-line no-console -- Workers observability keeps the console; this is a broken release file
      console.error(
        `No download on the page: ${LATEST_KEY} needs a version and a filename as text and a size as a number.`,
      );
    }
    return release;
  } catch (error) {
    // oxlint-disable-next-line no-console -- Workers observability keeps the console; this is a broken release file
    console.error(`No download on the page: ${LATEST_KEY} could not be read.`, error);
    return null;
  }
}

/** A stand-in for local work on the page, with a link that goes nowhere. Never in a production build. */
const SAMPLE_RELEASE: Release = {
  filename: 'agent-caffeine-0.2.3.dmg',
  href: '#',
  size: 6_400_000,
  version: '0.2.3',
};

/**
 * The newest published release, read on the server from the `MAC_FILES` R2
 * binding. The root route loads it once for every page. In local dev,
 * `VITE_FAKE_RELEASE=1` shows the sample release instead.
 */
export const getLatestRelease = createServerFn({ method: 'GET' }).handler(
  async (): Promise<Release | null> => {
    if (import.meta.env.DEV && import.meta.env.VITE_FAKE_RELEASE === '1') {
      return SAMPLE_RELEASE;
    }
    const { env } = await import('cloudflare:workers');
    const bucket = env['MAC_FILES'];
    return readLatestRelease(isBucket(bucket) ? bucket : undefined);
  },
);
