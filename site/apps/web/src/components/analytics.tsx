import { useEffect } from 'react';
import { loadOpenPanel } from '../lib/openpanel.ts';
import { onLiveHost, rememberUtm } from '../lib/track.ts';

/**
 * Counts page views with OpenPanel, on the live site only: a local run or a
 * preview loads nothing and sends nothing. Without
 * `VITE_OPENPANEL_CLIENT_ID` at build time it loads nothing either.
 */
export function Analytics() {
  useEffect(() => {
    rememberUtm();
    const clientId = import.meta.env.VITE_OPENPANEL_CLIENT_ID;
    if (clientId && onLiveHost()) {
      loadOpenPanel(clientId);
    }
  }, []);
  return null;
}
