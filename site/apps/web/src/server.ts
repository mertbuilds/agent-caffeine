import handler from '@tanstack/react-start/server-entry';
import { initWorkersLogger } from 'evlog/workers';
import { canonicalRedirect } from './lib/canonical.ts';
import { downloadRedirect, sendDownloadEvent } from './lib/download.ts';
import type { DownloadEvent } from './lib/download.ts';
import { macFileResponse } from './lib/mac-files.ts';
import type { MacFilesBucket } from './lib/mac-files.ts';
import { movedRedirect } from './lib/redirects.ts';
import { paraglideMiddleware } from './paraglide/server.js';

interface WorkerEnv {
  AXIOM_DATASET?: string;
  AXIOM_TOKEN?: string;
  MAC_FILES: MacFilesBucket;
  /** Lets the server count a download in OpenPanel (`/download`). */
  OPENPANEL_CLIENT_SECRET?: string;
}

interface ExecutionContextLike {
  waitUntil(promise: Promise<unknown>): void;
}

/** Counts downloads on the server, where no content blocker is in the way. Null without the project or the secret. */
function downloadCounter(
  env: WorkerEnv,
  ctx: ExecutionContextLike,
  log: { set(fields: Record<string, unknown>): void },
): ((event: DownloadEvent) => void) | null {
  const clientId = import.meta.env.VITE_OPENPANEL_CLIENT_ID;
  const clientSecret = env.OPENPANEL_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    return null;
  }
  return (event) => {
    log.set({ download: event.properties });
    ctx.waitUntil(sendDownloadEvent(event, clientId, clientSecret));
  };
}

let loggerReady = false;

async function initLoggerOnce(env: WorkerEnv): Promise<void> {
  if (loggerReady) {
    return;
  }
  loggerReady = true;
  if (env.AXIOM_TOKEN && env.AXIOM_DATASET) {
    const { createAxiomDrain } = await import('evlog/axiom');
    initWorkersLogger({
      drain: createAxiomDrain({
        dataset: env.AXIOM_DATASET,
        token: env.AXIOM_TOKEN,
      }),
      env: { service: 'web' },
    });
  } else {
    initWorkersLogger({ env: { service: 'web' } });
  }
}

export default {
  async fetch(request: Request, env: WorkerEnv, ctx: ExecutionContextLike): Promise<Response> {
    await initLoggerOnce(env);
    const { createWorkersLogger } = await import('evlog/workers');
    const log = createWorkersLogger(request, { executionCtx: ctx });
    const url = new URL(request.url);
    log.set({ method: request.method, path: url.pathname });
    try {
      const response =
        canonicalRedirect(url) ??
        movedRedirect(url) ??
        (await macFileResponse(request, url, env.MAC_FILES)) ??
        (await downloadRedirect(request, url, env.MAC_FILES, downloadCounter(env, ctx, log))) ??
        (await paraglideMiddleware(request, () => handler.fetch(request)));
      log.set({ status: response.status });
      return response;
    } catch (error) {
      log.error(error instanceof Error ? error : String(error));
      throw error;
    } finally {
      log.emit();
    }
  },
};
