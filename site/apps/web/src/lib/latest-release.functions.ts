import { createServerFn } from '@tanstack/react-start';
import { readLatestRelease } from './latest-release.ts';

/** The newest release, read on the Worker from the `MAC_FILES` bucket, for a route's loader. */
export const getLatestRelease = createServerFn({ method: 'GET' }).handler(async () => {
  // Imported here so the module stays out of the client bundle.
  const { env } = await import('cloudflare:workers');
  return readLatestRelease(env.MAC_FILES);
});
