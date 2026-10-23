import { SITE_URL } from './site.ts';

const CANONICAL_HOST = 'caffeinagent.com';
const WWW_HOST = 'www.caffeinagent.com';

/**
 * `www` is a custom domain on this same Worker, so the move to the apex
 * happens here rather than in DNS, and so does the move from http to https.
 * The path and the query ride along. A local server, a preview and workers.dev
 * have other hosts and are left alone.
 */
export function canonicalRedirect(url: URL): Response | null {
  const host = url.hostname;
  const insecure = host === CANONICAL_HOST && url.protocol === 'http:';
  if (host !== WWW_HOST && !insecure) {
    return null;
  }
  return Response.redirect(`${SITE_URL}${url.pathname}${url.search}`, 301);
}
