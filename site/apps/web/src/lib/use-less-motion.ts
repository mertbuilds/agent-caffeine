import { useSyncExternalStore } from 'react';

const LESS_MOTION = '(prefers-reduced-motion: reduce)';

function subscribe(onChange: () => void): () => void {
  const query = window.matchMedia(LESS_MOTION);
  query.addEventListener('change', onChange);
  return () => query.removeEventListener('change', onChange);
}

/** Whether the reader asks for less motion right now, read in the browser. */
export function lessMotion(): boolean {
  return window.matchMedia(LESS_MOTION).matches;
}

function lessMotionOnServer(): boolean {
  return false;
}

/**
 * Whether the reader asked for less motion. The server cannot know, so the
 * page is first drawn as the server drew it and changes once it has hydrated.
 */
export function useLessMotion(): boolean {
  return useSyncExternalStore(subscribe, lessMotion, lessMotionOnServer);
}
