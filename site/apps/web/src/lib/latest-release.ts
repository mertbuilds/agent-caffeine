import type { MacFilesBucket } from './mac-files.ts';

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

/** The key of the file `scripts/release.sh` writes last for every release. */
const LATEST_KEY = 'mac/latest.json';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
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
 * The release in a `latest.json` as `scripts/release.sh` writes it, or null
 * when the file does not hold a version and a filename as text and a size as a
 * number. The dmg is always served from this site under `/mac/`, whatever host
 * the file names.
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
 * The newest release from the bucket's `latest.json`. Null before the first
 * release, and when the file cannot be read or holds no release, so the site
 * never sends anyone to a download that is not there.
 */
export async function readLatestRelease(bucket: MacFilesBucket): Promise<Release | null> {
  try {
    const file = await bucket.get(LATEST_KEY);
    if (file === null || file.body === undefined) {
      return null;
    }
    const release = parseLatest(await new Response(file.body).json());
    if (release === null) {
      // oxlint-disable-next-line no-console -- Workers observability keeps the console; this is a broken release file
      console.error(
        `No download: ${LATEST_KEY} needs a version and a filename as text and a size as a number.`,
      );
    }
    return release;
  } catch (error) {
    // oxlint-disable-next-line no-console -- Workers observability keeps the console; this is a broken release file
    console.error(`No download: ${LATEST_KEY} could not be read.`, error);
    return null;
  }
}
