import { SITE_URL } from './site.ts';

/**
 * True for a Mac, the only place the app runs, as the browser itself tells it. Safari on an iPad
 * has the user agent of a Mac, and a screen that takes more than one touch, which no Mac has.
 */
export function isMacDevice(userAgent: string, maxTouchPoints: number): boolean {
  return userAgent.includes('Macintosh') && maxTouchPoints <= 1;
}

/** The link a visitor off a Mac copies or shares, to open on their Mac. Its tags tell these visits from the others. */
export const SEND_LINK = `${SITE_URL}/?utm_source=share&utm_medium=phone_popup&utm_campaign=download`;

/** What the popup needs of the button that opened it: to give focus back to it, if it is still in the page. */
export type Opener = Pick<HTMLElement, 'isConnected' | 'focus'>;

let opener: Opener | null = null;
const listeners = new Set<() => void>();

function set(next: Opener | null) {
  opener = next;
  for (const listener of listeners) {
    listener();
  }
}

/** Opens the page's one popup that says the app runs on a Mac. `button` is the download button that was pressed. */
export function openSendToMac(button: Opener) {
  set(button);
}

export function closeSendToMac() {
  set(null);
}

/** The button that opened the popup, or null while it is closed. A snapshot for `useSyncExternalStore`. */
export function sendToMacOpener(): Opener | null {
  return opener;
}

export function subscribeSendToMac(onChange: () => void): () => void {
  listeners.add(onChange);
  return () => {
    listeners.delete(onChange);
  };
}
