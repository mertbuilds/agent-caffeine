/**
 * The Mac app's files: the Sparkle feed (`appcast.xml`), `latest.json` and the
 * versioned dmgs. They live in the private R2 bucket behind `MAC_FILES` under
 * the same path as their URL (`/mac/appcast.xml` is the key
 * `mac/appcast.xml`). The shipped app has the feed URL baked in, so these URLs
 * never move.
 */
const PREFIX = '/mac/';
/**
 * The shape of a served file: one flat name under `/mac/`. Anything else is a
 * 404 before R2 is asked, which throws on a key that is too long.
 */
const FILE_PATH = /^\/mac\/[\w.-]{1,200}$/u;

/** A dmg is never replaced under its versioned name. */
const DMG_CACHE = 'public, max-age=31536000, immutable';
/** The feed and `latest.json` change with every release. */
const FEED_CACHE = 'public, max-age=300';

/**
 * A dmg's key, `mac/agent-caffeine-<version>-<build>.dmg`, or without the build. The first group is the name a person
 * should get on disk, less `.dmg`: the build number is only there to keep
 * every URL new, and next to the version it reads like a second version.
 */
const DMG_KEY = /^mac\/(agent-caffeine-\d+(?:\.\d+)*)(?:-\d+)?\.dmg$/u;

type ByteRange = { length: number; offset: number };

/** What R2 hands back. `body` is missing when a precondition failed. */
type MacFile = {
  body?: ReadableStream;
  httpEtag: string;
  size: number;
  writeHttpMetadata(headers: Headers): void;
};

/** The slice of the `MAC_FILES` R2 binding read here and by `downloadRedirect`. */
export type MacFilesBucket = {
  get(key: string, options?: { onlyIf: Headers; range?: ByteRange }): Promise<MacFile | null>;
  head(key: string): Promise<MacFile | null>;
};

function notFound(): Response {
  return new Response('Not found', { status: 404 });
}

function fileHeaders(file: MacFile, key: string): Headers {
  const headers = new Headers();
  file.writeHttpMetadata(headers);
  headers.set('accept-ranges', 'bytes');
  headers.set('cache-control', key.endsWith('.dmg') ? DMG_CACHE : FEED_CACHE);
  headers.set('etag', file.httpEtag);
  const savedName = DMG_KEY.exec(key)?.[1];
  if (savedName !== undefined) {
    headers.set('content-disposition', `attachment; filename="${savedName}.dmg"`);
  }
  return headers;
}

/**
 * One `bytes=` range against a file of `size` bytes. `null` for a header that
 * is malformed, asks for several ranges or another unit: HTTP lets the server
 * answer those with the whole file.
 */
function byteRange(header: string, size: number): ByteRange | 'unsatisfiable' | null {
  const match = /^bytes=(\d*)-(\d*)$/u.exec(header.trim());
  if (match === null) {
    return null;
  }
  const [, first = '', last = ''] = match;
  if (first === '') {
    if (last === '') {
      return null;
    }
    const length = Math.min(Number(last), size);
    return length === 0 ? 'unsatisfiable' : { length, offset: size - length };
  }
  const start = Number(first);
  if (last !== '' && Number(last) < start) {
    return null;
  }
  if (start >= size) {
    return 'unsatisfiable';
  }
  const end = last === '' ? size - 1 : Math.min(Number(last), size - 1);
  return { length: end - start + 1, offset: start };
}

/**
 * Reads the file, or the one slice of it in `range`. R2 checks the request's
 * conditional headers itself and leaves the body off when one fails.
 */
async function getFile(
  request: Request,
  key: string,
  bucket: MacFilesBucket,
  range: ByteRange | null,
): Promise<Response> {
  const file = await bucket.get(
    key,
    range === null ? { onlyIf: request.headers } : { onlyIf: request.headers, range },
  );
  if (file === null) {
    return notFound();
  }
  const headers = fileHeaders(file, key);
  if (file.body === undefined) {
    // A cached copy that is still current is a 304; a failed If-Match is a 412.
    const revalidating =
      request.headers.has('if-none-match') || request.headers.has('if-modified-since');
    return new Response(null, { headers, status: revalidating ? 304 : 412 });
  }
  if (range === null) {
    headers.set('content-length', String(file.size));
    return new Response(file.body, { headers });
  }
  headers.set('content-length', String(range.length));
  headers.set(
    'content-range',
    `bytes ${range.offset}-${range.offset + range.length - 1}/${file.size}`,
  );
  return new Response(file.body, { headers, status: 206 });
}

/**
 * Answers GET and HEAD for a file under `/mac/` from R2. `null` for any other
 * path, including the bare `/mac`, which is the site's 404 page.
 */
export async function macFileResponse(
  request: Request,
  url: URL,
  bucket: MacFilesBucket,
): Promise<Response | null> {
  if (!url.pathname.startsWith(PREFIX) || url.pathname.length === PREFIX.length) {
    return null;
  }
  if (!FILE_PATH.test(url.pathname)) {
    return notFound();
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response(null, { headers: { allow: 'GET, HEAD' }, status: 405 });
  }
  const key = url.pathname.slice(1);

  if (request.method === 'HEAD') {
    const file = await bucket.head(key);
    if (file === null) {
      return notFound();
    }
    const headers = fileHeaders(file, key);
    headers.set('content-length', String(file.size));
    return new Response(null, { headers });
  }

  const rangeHeader = request.headers.get('range');
  if (rangeHeader === null) {
    return getFile(request, key, bucket, null);
  }
  // The size is read first so a range past the end is a 416 rather than an R2
  // error. An `If-Range` that no longer matches drops the range, so a resumed
  // download of a replaced file starts over instead of splicing two together.
  const file = await bucket.head(key);
  if (file === null) {
    return notFound();
  }
  const ifRange = request.headers.get('if-range');
  if (ifRange !== null && ifRange !== file.httpEtag) {
    return getFile(request, key, bucket, null);
  }
  const range = byteRange(rangeHeader, file.size);
  if (range === 'unsatisfiable') {
    return new Response(null, {
      headers: { 'content-range': `bytes */${file.size}` },
      status: 416,
    });
  }
  return getFile(request, key, bucket, range);
}
