import { bindings, defineConfig } from 'cf/config';

export default defineConfig({
  worker: {
    // Static assets answer before the Worker, so a file under public/ would
    // shadow a route of the same path. `/mac/*` is the Mac app's files, read
    // from R2 below, and stays with the Worker whatever lands in public/.
    assets: {
      runWorkerFirst: ['/mac/*'],
    },
    compatibilityDate: '2026-09-01',
    compatibilityFlags: ['nodejs_compat'],
    // Custom entry: wraps @tanstack/react-start/server-entry with paraglide + evlog.
    entrypoint: 'src/server.ts',
    env: {
      // The Mac app's files (the Sparkle feed, `latest.json`, the versioned
      // dmgs) in the private bucket, answered by `macFileResponse` in
      // src/lib/mac-files.ts and read by `readLatestRelease` in
      // src/lib/latest-release.ts. The key is the URL path without its leading
      // slash: /mac/appcast.xml is `mac/appcast.xml`. The bucket name is a
      // secret (docs/adr/0002 at the repository root): a deploy reads it from
      // MAC_FILES_BUCKET, which `cf:deploy` requires. Without it, as in `vite
      // dev`, the tests and CI builds, the binding is a local simulation named
      // `mac-files` under .cloudflare/state (README.md).
      MAC_FILES: bindings.r2({ name: process.env.MAC_FILES_BUCKET || 'mac-files' }),
    },
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
