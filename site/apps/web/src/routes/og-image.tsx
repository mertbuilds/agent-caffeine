import { fontWeight, leading } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { createFileRoute, notFound } from '@tanstack/react-router';
import { PRICE } from '../lib/pricing.ts';
import { m } from '../paraglide/messages.js';

/**
 * The picture for link previews, 1200 by 630, in the dark look of the page.
 * Only the dev server draws it: `scripts/og-image.sh` takes its picture and
 * saves it as `public/og.png`. A production build answers with the 404 and
 * drops its code.
 */
export const Route = createFileRoute('/og-image')({
  beforeLoad: () => {
    if (!import.meta.env.DEV) {
      throw notFound();
    }
  },
  component: import.meta.env.DEV ? OgImage : () => null,
  head: () => ({
    meta: [{ content: 'noindex, nofollow', name: 'robots' }],
  }),
});

const GRID_LINE = 'rgba(255, 255, 255, 0.06)';
const MUTED = '#a3a3a3';

const styles = create({
  brand: {
    alignItems: 'center',
    color: MUTED,
    display: 'flex',
    fontSize: 30,
    gap: 16,
    lineHeight: leading.none,
  },
  copy: {
    display: 'flex',
    flexDirection: 'column',
    gap: 40,
    position: 'relative',
  },
  glow: {
    backgroundImage: 'radial-gradient(closest-side, rgba(42, 112, 224, 0.55), transparent)',
    height: 640,
    position: 'absolute',
    right: -60,
    top: '50%',
    transform: 'translateY(-50%)',
    width: 640,
  },
  grid: {
    backgroundImage: `linear-gradient(${GRID_LINE} 1px, transparent 1px), linear-gradient(90deg, ${GRID_LINE} 1px, transparent 1px)`,
    backgroundSize: '40px 40px',
    inset: 0,
    maskImage: 'radial-gradient(ellipse 55% 85% at 80% 48%, black 10%, transparent 75%)',
    position: 'absolute',
  },
  headline: {
    fontSize: 76,
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.02em',
    lineHeight: 1.06,
  },
  highlight: {
    color: '#5aa2ff',
  },
  icon: {
    filter: 'drop-shadow(0 24px 32px rgba(6, 24, 74, 0.6))',
    height: 380,
    position: 'absolute',
    right: 70,
    top: '50%',
    transform: 'translateY(-50%) rotate(5deg)',
    width: 380,
  },
  mark: {
    height: 44,
    width: 44,
  },
  offer: {
    color: MUTED,
    fontSize: 34,
    lineHeight: leading.none,
  },
  // Fixed over everything else the root document draws, at the picture's size.
  page: {
    alignItems: 'center',
    backgroundColor: '#000000',
    color: '#ffffff',
    display: 'flex',
    height: 630,
    left: 0,
    overflow: 'hidden',
    paddingInline: 80,
    position: 'fixed',
    top: 0,
    width: 1200,
    zIndex: 50,
  },
});

function OgImage() {
  return (
    <main id="main" {...props(styles.page)}>
      <div aria-hidden="true" {...props(styles.grid)} />
      <div aria-hidden="true" {...props(styles.glow)} />
      <div {...props(styles.copy)}>
        <p {...props(styles.brand)}>
          <img alt={''} height={44} src="/icon.png" width={44} {...props(styles.mark)} />
          {m.app_name()}
        </p>
        <h1 {...props(styles.headline)}>
          {m.og_headline_start()}
          <br />
          <span {...props(styles.highlight)}>
            {m.og_headline_middle()}
            <br />
            {m.og_headline_end()}
          </span>
        </h1>
        <p {...props(styles.offer)}>{m.og_offer({ price: PRICE })}</p>
      </div>
      <img alt={''} height={380} src="/icon-1024.png" width={380} {...props(styles.icon)} />
    </main>
  );
}
