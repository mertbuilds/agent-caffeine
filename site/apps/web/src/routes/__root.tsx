import { fontUrls } from '@caffeinagent/ui/fonts';
import { colors, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { createRootRoute, HeadContent, Outlet, Scripts } from '@tanstack/react-router';
import { useEffect, type ReactNode } from 'react';
import { Analytics } from '../components/analytics.tsx';
import { HashScroll } from '../components/hash-scroll.tsx';
import { NotFound } from '../components/not-found.tsx';
import { SendToMacPopup } from '../components/send-to-mac-popup.tsx';
import { SiteHeader } from '../components/site-header.tsx';
import { PRICE } from '../lib/pricing.ts';
import { getLatestRelease } from '../lib/latest-release.functions.ts';
import { THEME_SCRIPT } from '../lib/theme.ts';
import { m } from '../paraglide/messages.js';
import { getLocale } from '../paraglide/runtime.js';
import fontsStylesheet from '@caffeinagent/ui/fonts-optional.css?url';
import '@caffeinagent/ui/tokens.css';
import '@caffeinagent/ui/theme.css';
import '../styles/preflight.css';
import '../app.css';
import '../styles/scenes.css';
import '../styles/article.css';

const SITE_URL = 'https://caffeinagent.com';
const SHARE_IMAGE = `${SITE_URL}/og.png`;

if (import.meta.env.DEV && typeof window !== 'undefined') {
  // Dev-only: StyleX HMR runtime injects styles; production CSS is emitted into app.css at build.
  void import('virtual:stylex:runtime');
  // Dev-only: devknobs emulates color scheme, motion, contrast, locale, geo and
  // layout from inside the page (⇧K toggles it), and grabs an element's context
  // for an agent (⇧G).
  // oxlint-disable-next-line unicorn/prefer-top-level-await -- awaiting here would stop the route module from evaluating if the chunk fails
  void import('devknobs')
    .then(({ mount }) => mount())
    // oxlint-disable-next-line no-console -- the browser console is the only channel this dev-only failure has
    .catch((error: unknown) => console.warn('devknobs failed to load', error));
}

export const Route = createRootRoute({
  component: RootComponent,
  head: ({ matches }) => {
    const shareDescription = m.meta_share_description({ price: PRICE });
    return {
      links: [
        { href: '/icon.png', rel: 'icon', type: 'image/png' },
        // The fonts load with the document instead of after the stylesheet asks
        // for them, which `font-display: optional` needs to use them at all.
        // Fonts are fetched in CORS mode, so the preload has to be as well or
        // the stylesheet cannot reuse it. The @font-face rules are linked
        // rather than imported: in dev an imported stylesheet is applied a
        // second time around hydration. `precedence` for the same reason as
        // the dev StyleX link below.
        { href: fontsStylesheet, precedence: 'default', rel: 'stylesheet' },
        ...fontUrls.map((href) => ({
          as: 'font',
          crossOrigin: 'anonymous' as const,
          href,
          rel: 'preload',
          type: 'font/woff2',
        })),
        // Dev-only: link the unplugin's compiled CSS so SSR HTML is styled on first
        // paint (the virtual:stylex:runtime import only injects after hydration;
        // without this link every refresh flashes unstyled). Production CSS is
        // emitted into app.css at build, so the link is dev-only.
        // `precedence` is required: React 19 hoists SSR stylesheets with
        // data-precedence, and a client link without the prop hydration-mismatches
        // (which silently breaks event wiring on the whole tree).
        ...(import.meta.env.DEV
          ? [{ href: '/virtual:stylex.css', precedence: 'default', rel: 'stylesheet' }]
          : []),
      ],
      meta: [
        // oxlint-disable-next-line text-encoding-identifier-case -- HTML meta charset must be "utf-8"
        { charSet: 'utf-8' },
        { content: 'width=device-width, initial-scale=1', name: 'viewport' },
        // Only the root matches an address no route has: that is the 404.
        { title: matches.length === 1 ? m.notfound_meta_title() : m.meta_title() },
        { content: m.meta_description({ price: PRICE }), name: 'description' },
        { content: m.app_name(), property: 'og:title' },
        { content: shareDescription, property: 'og:description' },
        { content: 'website', property: 'og:type' },
        { content: SHARE_IMAGE, property: 'og:image' },
        { content: '1200', property: 'og:image:width' },
        { content: '630', property: 'og:image:height' },
        { content: m.meta_share_image_alt(), property: 'og:image:alt' },
        { content: 'summary_large_image', name: 'twitter:card' },
        { content: m.app_name(), name: 'twitter:title' },
        { content: shareDescription, name: 'twitter:description' },
        { content: SHARE_IMAGE, name: 'twitter:image' },
      ],
    };
  },
  // The download buttons of every page read it (components/download-button.tsx).
  loader: () => getLatestRelease(),
  notFoundComponent: NotFound,
  staleTime: Infinity,
});

const styles = create({
  // Out of sight until it has the keyboard's focus, then a pill at the top left.
  skipLink: {
    backgroundColor: colors.bg,
    borderRadius: radius.full,
    boxShadow: `0 8px 32px ${colors.shadow}`,
    clip: { ':focus-visible': 'auto', default: 'rect(0, 0, 0, 0)' },
    fontSize: text.sm,
    height: { ':focus-visible': 'auto', default: '1px' },
    left: spacing.s2,
    lineHeight: text.smLeading,
    margin: { ':focus-visible': 0, default: '-1px' },
    overflow: { ':focus-visible': 'visible', default: 'hidden' },
    paddingBlock: { ':focus-visible': spacing.s1_5, default: 0 },
    paddingInline: { ':focus-visible': spacing.s4, default: 0 },
    position: { ':focus-visible': 'fixed', default: 'absolute' },
    textDecorationLine: 'none',
    top: spacing.s2,
    whiteSpace: { ':focus-visible': 'normal', default: 'nowrap' },
    width: { ':focus-visible': 'auto', default: '1px' },
    zIndex: 40,
  },
});

function RootComponent() {
  // Marks hydration completion; forms rely on React handlers (preventDefault),
  // so e2e tests wait for html[data-hydrated] before interacting.
  useEffect(() => {
    document.documentElement.dataset['hydrated'] = 'true';
  }, []);
  return (
    <RootDocument>
      <Outlet />
    </RootDocument>
  );
}

function RootDocument({ children }: { children: ReactNode }) {
  return (
    // The head's script sets `data-theme` before hydration; that one attribute may differ.
    <html lang={getLocale()} suppressHydrationWarning>
      <head>
        {/* Before anything paints, so a kept theme is never preceded by the other. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
        <HeadContent />
      </head>
      <body>
        <a href="#main" {...props(styles.skipLink)}>
          {m.root_skip_link()}
        </a>
        <SiteHeader />
        {children}
        <HashScroll />
        <SendToMacPopup />
        <Analytics />
        <Scripts />
      </body>
    </html>
  );
}
