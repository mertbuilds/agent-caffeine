export type Release = {
  version: string;
  /** The path of the dmg on this site, under `/mac/`. */
  href: string;
  /** The name the browser saves the dmg under. */
  filename: string;
  size: number;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function hrefFor(url: unknown, filename: string): string {
  if (typeof url === "string" && URL.canParse(url)) {
    const path = new URL(url).pathname;
    if (path.startsWith("/mac/")) return path;
  }
  return `/mac/${filename}`;
}

/**
 * The newest published release, from the `latest.json` the release script writes.
 * Null before the first release, without `MAC_FILES_ORIGIN`, or when the file cannot
 * be read, so the page never links to a download that is not there.
 */
export async function getLatestRelease(): Promise<Release | null> {
  const origin = process.env.MAC_FILES_ORIGIN;
  if (!origin) return null;
  try {
    const response = await fetch(`${origin}/mac/latest.json`, { next: { revalidate: 3600 } });
    if (!response.ok) return null;
    const data: unknown = await response.json();
    if (!isRecord(data)) return null;
    const { version, filename, size, url } = data;
    if (typeof version !== "string" || typeof filename !== "string" || typeof size !== "number") {
      return null;
    }
    return { version, href: hrefFor(url, filename), filename, size };
  } catch {
    return null;
  }
}

function formatSize(bytes: number): string {
  if (bytes < 1_000_000) return `${Math.round(bytes / 1000)} kilobytes`;
  return `${(bytes / 1_000_000).toFixed(1)} megabytes`;
}

export function releaseDetails(release: Release): string {
  return `Version ${release.version} · ${formatSize(release.size)} · macOS 13 or later, Apple silicon and Intel`;
}
