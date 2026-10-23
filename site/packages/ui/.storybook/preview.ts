import type { Preview } from '@storybook/react-vite';
import type { CDPSession } from '@vitest/browser-playwright';
import '../src/tokens.css';
import '../src/theme.css';
import '../src/fonts.css';
import './preview.css';

const dev = (import.meta as { env?: { DEV?: boolean } }).env?.DEV === true;
const stylexCssPath = '/virtual:stylex.css';

if (dev) {
  // Hot CSS reloads for StyleX in dev; the stylesheet itself is linked in
  // previewHead (see main.ts). No-op in production builds.
  void import('virtual:stylex:runtime');
}

// In dev, StyleX collects a module's CSS when Vite transforms it. The linked
// stylesheet is fetched at page load, before the story's modules are
// transformed, and the runtime refreshes it only after an HMR event polled
// every 150ms, so a play function could read computed styles before the rules
// arrive (it did in CI). By beforeEach the story's modules are loaded, so this
// fetch has every rule the story needs. It gets its own element ahead of the
// runtime's, so a late runtime refresh cannot drop these rules and HMR updates
// still win.
const loadStylexCss = async () => {
  if (!dev) {
    return;
  }
  const response = await fetch(stylexCssPath, { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`StyleX dev CSS request failed with ${response.status}.`);
  }
  let style = document.querySelector<HTMLStyleElement>('style[data-stylex-story]');
  if (!style) {
    style = document.createElement('style');
    style.dataset.stylexStory = '';
    const link = document.querySelector(`link[href^="${stylexCssPath}"]`);
    if (link) {
      link.after(style);
    } else {
      document.head.append(style);
    }
  }
  const css = await response.text();
  style.textContent = css;
  // The runtime's own element comes later and wins, but its first fetch can
  // land mid-load, after a component compiled and before the tokens it uses:
  // same class names, unresolved token values. This fetch is newer.
  const runtimeStyle = document.querySelector<HTMLStyleElement>('style#__stylex_virtual__');
  if (runtimeStyle) {
    runtimeStyle.textContent = css;
  }
};

// Story tests share one page, and stories render at the canvas's top-left
// corner. Storybook parks the real pointer at (-1000, -1000) before each test,
// but Chromium keeps hit-testing hover at the last in-viewport position, so
// whatever renders there next gains :hover a frame later (after a style change
// such as color scheme emulation, too). Park it in the viewport's bottom-right
// corner instead, away from story content. Only the Vitest run has
// vitest/browser.
const parkPointer = async () => {
  if (!dev) {
    return;
  }
  const browser = await import('vitest/browser').catch(() => null);
  if (!browser) {
    return;
  }
  // Playwright's session type: vitest/browser gets the same method types only
  // through a module augmentation, which oxlint's type check resolves on some
  // runs and not others.
  const session = browser.cdp() as CDPSession;
  const { cssLayoutViewport } = await session.send('Page.getLayoutMetrics');
  await session.send('Input.dispatchMouseEvent', {
    type: 'mouseMoved',
    x: cssLayoutViewport.clientWidth - 1,
    y: cssLayoutViewport.clientHeight - 1,
  });
};

const preview: Preview = {
  beforeEach: [loadStylexCss, parkPointer],
  parameters: {
    backgrounds: { disable: true },
  },
};

export default preview;
