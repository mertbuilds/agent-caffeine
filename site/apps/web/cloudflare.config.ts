import { defineConfig } from 'cf/config';

export default defineConfig({
  worker: {
    compatibilityDate: '2026-09-01',
    compatibilityFlags: ['nodejs_compat'],
    // Custom entry: wraps @tanstack/react-start/server-entry with paraglide + evlog.
    entrypoint: 'src/server.ts',
    name: 'caffeinagent-web',
    // With no evlog drain bound, evlog only logs to the console and this keeps those
    // logs. Turn it off once AXIOM_TOKEN and AXIOM_DATASET are bound, or logs duplicate.
    observability: {
      enabled: true,
      logs: {
        enabled: true,
        headSamplingRate: 1,
      },
    },
    // Explicit because cf turns both off once `domains` is set, and preview URLs
    // let a pull request be looked at before it merges.
    previewUrls: true,
    workersDev: true,
  },
});
