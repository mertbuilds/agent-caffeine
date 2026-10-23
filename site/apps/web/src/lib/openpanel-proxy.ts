import { OPENPANEL_API_URL } from './site.ts';

const PREFIX = '/api/op';
/** Where OpenPanel serves its tracker and its session recorder. */
const SCRIPT_ORIGIN = 'https://openpanel.dev';
const SCRIPTS = new Set(['/op1.js', '/op1-replay.js']);

export type Send = (input: string, init?: RequestInit) => Promise<Response>;

function notFound(): Response {
  return Response.json({ error: 'Not found' }, { status: 404 });
}

async function script(path: string, search: string, send: Send): Promise<Response> {
  const upstream = await send(`${SCRIPT_ORIGIN}${path}${search}`);
  if (!upstream.ok) {
    return Response.json(
      { error: `${SCRIPT_ORIGIN}${path} answered ${upstream.status}` },
      { status: 502 },
    );
  }
  return new Response(await upstream.text(), {
    headers: {
      'Cache-Control': 'public, max-age=86400, stale-while-revalidate=86400',
      'Content-Type': 'text/javascript',
    },
  });
}

/** The headers OpenPanel reads: the project, the page's origin, the browser and the visitor's address for the country. */
function forwardHeaders(request: Request, url: URL): Headers {
  const headers = new Headers({
    'Content-Type': 'application/json',
    'openpanel-client-id': request.headers.get('openpanel-client-id') ?? '',
    origin: request.headers.get('origin') ?? url.origin,
    'User-Agent': request.headers.get('user-agent') ?? '',
  });
  const ip =
    request.headers.get('cf-connecting-ip') ??
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  if (ip) {
    headers.set('openpanel-client-ip', ip);
  }
  return headers;
}

/**
 * The browser's way to OpenPanel, on this site's own address. `/api/op/op1.js`
 * and `/api/op/op1-replay.js` are the scripts, kept a day; a path with
 * `/track` in it goes on to the OpenPanel server; anything else is a 404.
 */
export async function openPanelProxy(request: Request, send: Send = fetch): Promise<Response> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(`${PREFIX}/`)) {
    return notFound();
  }
  const path = url.pathname.slice(PREFIX.length);
  if (request.method === 'GET' && SCRIPTS.has(path)) {
    return script(path, url.search, send);
  }
  const track = path.indexOf('/track');
  if (track === -1) {
    return notFound();
  }
  const upstream = await send(`${OPENPANEL_API_URL}${path.slice(track)}`, {
    body: request.method === 'POST' ? await request.text() : null,
    headers: forwardHeaders(request, url),
    method: request.method,
  });
  return new Response(await upstream.text(), {
    headers: { 'Content-Type': upstream.headers.get('content-type') ?? 'application/json' },
    status: upstream.status,
  });
}
