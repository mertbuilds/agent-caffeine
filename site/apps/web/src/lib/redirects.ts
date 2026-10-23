/**
 * Addresses that moved, answered with a 301 before the app renders. The app,
 * the README and old links open `/support`. Support is gone, so it goes to the price.
 */
const MOVED: Readonly<Record<string, string>> = {
  '/support': '/#pricing',
};

export function movedRedirect(url: URL): Response | null {
  const path = url.pathname.length > 1 ? url.pathname.replace(/\/$/, '') : url.pathname;
  const target = MOVED[path];
  return target === undefined ? null : Response.redirect(new URL(target, url).href, 301);
}
