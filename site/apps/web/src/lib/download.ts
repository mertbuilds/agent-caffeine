import type { Release } from './latest-release.ts';
import { readLatestRelease } from './latest-release.ts';
import type { MacFilesBucket } from './mac-files.ts';

/** The address every download button links to. The Worker sends the browser on to the dmg there. */
export const DOWNLOAD_PATH = '/download';

/** Where a request for the download goes: the dmg of the newest release under `/mac/`, or the home page while there is none. */
export function downloadTarget(release: Release | null): string {
  if (release === null || !release.href.startsWith('/mac/')) {
    return '/';
  }
  return release.href;
}

/**
 * Answers `/download` with a 302 to the newest dmg, or to the home page while
 * there is none, never cached. `null` for any other path.
 */
export async function downloadRedirect(
  request: Request,
  url: URL,
  bucket: MacFilesBucket,
): Promise<Response | null> {
  if (url.pathname !== DOWNLOAD_PATH) {
    return null;
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response(null, { headers: { allow: 'GET, HEAD' }, status: 405 });
  }
  const location = downloadTarget(await readLatestRelease(bucket));
  return new Response(null, {
    headers: { 'cache-control': 'no-store', location },
    status: 302,
  });
}
