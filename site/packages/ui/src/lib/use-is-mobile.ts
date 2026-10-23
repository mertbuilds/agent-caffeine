import { useSyncExternalStore } from 'react';

/**
 * A phone, in the terms that matter to a Tip: its primary input cannot hover.
 * Opening on hover means nothing there, so a wide tablet needs the sheet as
 * much as a narrow phone does.
 */
const MOBILE_QUERY = '(hover: none)';

const subscribe = (onChange: () => void) => {
  if (typeof matchMedia !== 'function') {
    return () => {};
  }
  const query = matchMedia(MOBILE_QUERY);
  query.addEventListener('change', onChange);
  return () => query.removeEventListener('change', onChange);
};

const getSnapshot = () => typeof matchMedia === 'function' && matchMedia(MOBILE_QUERY).matches;

// The server has no input device: it renders the desktop shape, hydration
// renders the same, and React re-renders right after if the device differs.
const getServerSnapshot = () => false;

/** Whether the reader's primary input cannot hover (a phone or a tablet). */
export const useIsMobile = () => useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
