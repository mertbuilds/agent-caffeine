import handler from '@tanstack/react-start/server-entry';
import { initWorkersLogger } from 'evlog/workers';
import { movedRedirect } from './lib/redirects.ts';
import { paraglideMiddleware } from './paraglide/server.js';

interface WorkerEnv {
  AXIOM_DATASET?: string;
  AXIOM_TOKEN?: string;
}

interface ExecutionContextLike {
  waitUntil(promise: Promise<unknown>): void;
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
        movedRedirect(url) ?? (await paraglideMiddleware(request, () => handler.fetch(request)));
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
