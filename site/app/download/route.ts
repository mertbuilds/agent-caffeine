import { after } from "next/server";
import { decideDownload, trackRequest, TRACK_TIMEOUT_MS, type DownloadEvent } from "@/lib/download";
import { getLatestRelease } from "@/lib/release";

export const dynamic = "force-dynamic";

async function count(event: DownloadEvent, clientId: string, clientSecret: string) {
  const { url, init } = trackRequest(event, clientId, clientSecret);
  try {
    const response = await fetch(url, { ...init, signal: AbortSignal.timeout(TRACK_TIMEOUT_MS) });
    if (!response.ok) console.error(`download: ${url} answered ${response.status}`);
  } catch (error) {
    console.error(`download: could not reach ${url}`, error);
  }
}

/** Counts the download of a browser on a Mac on the server, where no content blocker is in the way, and sends every request on to the dmg. */
async function download(request: Request): Promise<Response> {
  const clientId = process.env.NEXT_PUBLIC_OPENPANEL_CLIENT_ID;
  const clientSecret = process.env.OPENPANEL_CLIENT_SECRET;
  const { redirectTo, event } = decideDownload({
    host: request.headers.get("host"),
    method: request.method,
    headers: request.headers,
    search: new URL(request.url).search,
    release: await getLatestRelease(),
    secretSet: Boolean(clientId && clientSecret),
  });
  if (event !== null && clientId && clientSecret) {
    after(() => count(event, clientId, clientSecret));
  }
  return new Response(null, { status: 302, headers: { Location: redirectTo, "Cache-Control": "no-store" } });
}

export const GET = download;
export const HEAD = download;
