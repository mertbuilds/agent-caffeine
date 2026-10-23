/** Where the browser reaches OpenPanel: this site's own proxy (`routes/api/op/$.ts`), so a content blocker does not drop it. */
const API_URL = '/api/op';
/** The share of sessions that are recorded. The owner wants every session during launch; lower it after. */
const REPLAY_SAMPLE_RATE = 1;
/** How often the recorder sends what it has, in milliseconds. */
const REPLAY_FLUSH_INTERVAL_MS = 10_000;

/**
 * Starts OpenPanel: the calls wait in `window.op.q` until `op1.js` lands and
 * plays them, the `init` first. The recorder is a second script, fetched only
 * after the first one runs. Page text is the same for every reader, so it is
 * not masked.
 */
export function loadOpenPanel(clientId: string): void {
  if (typeof window.op !== 'function') {
    const queue: Array<Array<unknown>> = [];
    window.op = Object.assign(
      (...args: Array<unknown>) => {
        queue.push(args);
      },
      { q: queue },
    );
  }
  window.op('init', {
    apiUrl: API_URL,
    clientId,
    sessionReplay: {
      enabled: true,
      flushIntervalMs: REPLAY_FLUSH_INTERVAL_MS,
      maskAllInputs: true,
      maskAllText: false,
      sampleRate: REPLAY_SAMPLE_RATE,
      scriptUrl: `${API_URL}/op1-replay.js`,
    },
    trackAttributes: false,
    trackOutgoingLinks: false,
    trackScreenViews: true,
  });
  const script = document.createElement('script');
  script.async = true;
  script.src = `${API_URL}/op1.js`;
  document.head.append(script);
}
