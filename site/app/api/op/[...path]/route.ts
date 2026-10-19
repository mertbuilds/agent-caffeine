import { createHash } from "node:crypto";
import { createRouteHandler } from "@openpanel/nextjs/server";
import { OPENPANEL_API_URL } from "@/lib/site";

const handler = createRouteHandler({
  apiUrl: OPENPANEL_API_URL,
});

/** The session recorder that `op1.js` loads when recording is on. The handler above serves only `op1.js`, from the same place. */
const REPLAY_PATH = "/op1-replay.js";
const REPLAY_SOURCE = `https://openpanel.dev${REPLAY_PATH}`;

async function replayScript(): Promise<Response> {
  try {
    const upstream = await fetch(REPLAY_SOURCE, { next: { revalidate: 86400 } });
    if (!upstream.ok) {
      console.error(`api/op: ${REPLAY_SOURCE} answered ${upstream.status}`);
      return Response.json({ error: "Failed to fetch script" }, { status: 502 });
    }
    const script = await upstream.text();
    return new Response(script, {
      headers: {
        "Content-Type": "text/javascript",
        "Cache-Control": "public, max-age=86400, stale-while-revalidate=86400",
        ETag: `"${createHash("md5").update(script).digest("hex")}"`,
      },
    });
  } catch (error) {
    console.error(`api/op: could not fetch ${REPLAY_SOURCE}`, error);
    return Response.json({ error: "Failed to fetch script" }, { status: 502 });
  }
}

export function GET(request: Request) {
  if (new URL(request.url).pathname.endsWith(REPLAY_PATH)) {
    return replayScript();
  }
  return handler(request);
}

export const POST = handler;
