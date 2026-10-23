import { breakpoints, colors, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link, useLocation } from '@tanstack/react-router';
import { useEffect, useRef, useState } from 'react';
import { flushSync } from 'react-dom';
import { morph } from '../lib/morph.ts';
import { m } from '../paraglide/messages.js';
import { DownloadButton, useRelease, WithAppleMark } from './download-button.tsx';
import { SiteMenu } from './site-menu.tsx';

/**
 * How far down the page the pill takes over, and how far back up the open
 * header returns. The gap between them keeps a page resting near one line
 * from flipping between the two.
 */
const PILL_FROM = 48;
const OPEN_FROM = 16;

/** The home page's sections in the order they stand. `ids` are the sections a link stands for. */
const SECTIONS = [
  {
    hash: '#examples',
    ids: ['examples'],
    label: () => m.header_examples(),
    name: 'header-examples',
  },
  { hash: '#agents', ids: ['agents'], label: () => m.header_agents(), name: 'header-agents' },
  {
    hash: '#features',
    ids: ['features', 'small-things'],
    label: () => m.header_features(),
    name: 'header-features',
  },
  { hash: '#demo', ids: ['demo'], label: () => m.header_demo(), name: 'header-demo' },
  { hash: '#pricing', ids: ['pricing'], label: () => m.header_pricing(), name: 'header-pricing' },
  { hash: '#faq', ids: ['faq'], label: () => m.header_faq(), name: 'header-faq' },
] as const;

/** The line across the window that a section must lie on to be the one in view: 30% of the way down. */
const VIEW_LINE = '-30% 0px -70% 0px';

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';
const LESS_TRANSPARENCY = '@media (prefers-reduced-transparency: reduce)';

/** An item the morph carries, by the name a view transition knows it by. */
function morphName(name: string) {
  return { 'data-morph': name, style: { viewTransitionName: name } };
}

const styles = create({
  bar: {
    alignItems: 'center',
    boxSizing: 'border-box',
    pointerEvents: 'auto',
    position: 'relative',
  },
  barOpen: {
    columnGap: spacing.s4,
    display: 'grid',
    gridAutoColumns: 'auto',
    gridAutoFlow: 'column',
    gridTemplateColumns: {
      [breakpoints.md]: 'minmax(0, 1fr) auto minmax(0, 1fr)',
      default: 'minmax(0, 1fr) auto',
    },
    paddingInline: spacing.s4,
  },
  barPill: {
    alignSelf: 'center',
    display: 'flex',
    gap: { [breakpoints.md]: spacing.s6, default: spacing.s3 },
    height: spacing.s10,
    justifySelf: 'center',
    padding: spacing.s1_5,
  },
  current: {
    color: colors.fg,
  },
  end: {
    alignItems: 'center',
    display: 'inline-flex',
    gap: spacing.s2,
    justifySelf: 'end',
  },
  header: {
    display: 'grid',
    height: spacing.s14,
    marginBottom: `calc(-1 * ${spacing.s14})`,
    pointerEvents: 'none',
    position: 'sticky',
    top: 0,
    zIndex: 30,
  },
  hidden: {
    display: 'none',
  },
  home: {
    alignItems: 'center',
    color: { ':hover': colors.fg, default: colors.muted },
    display: 'inline-flex',
    fontSize: text.sm,
    gap: spacing.s2,
    justifySelf: 'start',
    lineHeight: text.smLeading,
    maxWidth: '100%',
    minWidth: 0,
    position: 'relative',
    textDecorationLine: 'none',
  },
  homePill: {
    borderRadius: radius.full,
  },
  icon: {
    height: spacing.s6,
    width: spacing.s6,
  },
  iconPill: {
    height: spacing.s7,
    width: spacing.s7,
  },
  link: {
    color: { ':hover': colors.fg, default: colors.muted },
    fontSize: text.sm,
    lineHeight: text.smLeading,
    textDecorationLine: 'none',
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
      [LESS_MOTION]: 'none',
    },
    transitionTimingFunction: 'ease-out',
    whiteSpace: 'nowrap',
  },
  mark: {
    borderRadius: '12.5%',
    display: 'flex',
    flexShrink: 0,
    overflow: 'hidden',
  },
  markPill: {
    borderRadius: radius.full,
  },
  name: {
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  nav: {
    alignItems: 'center',
    display: { [breakpoints.md]: 'flex', default: 'none' },
    gap: spacing.s6,
    position: 'relative',
  },
  primary: {
    display: 'inline-flex',
  },
  // The ground behind the row: nothing while the header is open, and the pill once it gathers.
  surface: {
    backdropFilter: { default: 'blur(16px) saturate(1.4)', [LESS_TRANSPARENCY]: 'none' },
    backgroundColor: {
      default: `color-mix(in srgb, ${colors.bg} 65%, transparent)`,
      [LESS_TRANSPARENCY]: colors.bg,
    },
    borderColor: `color-mix(in srgb, ${colors.fg} 10%, transparent)`,
    borderRadius: 0,
    borderStyle: 'solid',
    borderWidth: '1px',
    boxShadow: `0 8px 32px ${colors.shadow}`,
    boxSizing: 'border-box',
    inset: 0,
    opacity: 0,
    pointerEvents: 'none',
    position: 'absolute',
  },
  surfacePill: {
    borderRadius: '20px',
    opacity: 1,
  },
});

/**
 * The name and the way home at the left, the home page's sections in the
 * middle, and the download at the right. The link of the section in view takes
 * the text's own colour. Once the page has run a little way under it, the
 * items gather into a pill in the middle, the mark alone for the name, and
 * open back out near the top (lib/morph.ts). A window too narrow for the links
 * has the menu's button at the far edge with the links in the menu it opens.
 *
 * The blur sits on a ground of its own behind the items, never on the header
 * or anything around the page, which Safari on iOS can draw wrong.
 */
export function SiteHeader() {
  const [pill, setPill] = useState(false);
  const bar = useRef<HTMLDivElement>(null);
  const surface = useRef<HTMLSpanElement>(null);
  const mark = useRef<HTMLSpanElement>(null);
  const [inView, setInView] = useState<string | null>(null);
  const pathname = useLocation({ select: (location) => location.pathname });
  const release = useRelease();
  const links = SECTIONS.map((section) => ({
    current: pathname === '/' && section.hash === inView,
    href: `/${section.hash}`,
    label: section.label(),
    name: section.name,
  }));

  // One observer for every section. Between two sections the last one stays
  // in view; above the first there is none.
  useEffect(() => {
    if (pathname !== '/') {
      return;
    }
    const hashes = new Map<Element, string>();
    for (const section of SECTIONS) {
      for (const id of section.ids) {
        const element = document.getElementById(id);
        if (element !== null) {
          hashes.set(element, section.hash);
        }
      }
    }
    const first = document.getElementById(SECTIONS[0].ids[0]);
    const on = new Set<Element>();
    const observer = new IntersectionObserver(
      (entries) => {
        let above = false;
        for (const entry of entries) {
          if (entry.isIntersecting) {
            on.add(entry.target);
          } else {
            on.delete(entry.target);
          }
          if (entry.target === first) {
            above =
              !entry.isIntersecting && entry.boundingClientRect.top > (entry.rootBounds?.top ?? 0);
          }
        }
        const [element] = on;
        if (element !== undefined) {
          setInView(hashes.get(element) ?? null);
        } else if (above) {
          setInView(null);
        }
      },
      { rootMargin: VIEW_LINE },
    );
    for (const element of hashes.keys()) {
      observer.observe(element);
    }
    return () => observer.disconnect();
  }, [pathname]);

  // Only a change between the two lines moves anything; the page as it first loads is drawn as it is.
  useEffect(() => {
    let current = false;
    function update(first: boolean) {
      const next = window.scrollY > (current ? OPEN_FROM : PILL_FROM);
      if (next === current) {
        return;
      }
      current = next;
      const root = bar.current;
      const ground = surface.current;
      if (first || root === null || ground === null) {
        setPill(next);
        return;
      }
      morph({
        gather: next,
        live: mark.current === null ? [] : [mark.current],
        root,
        surface: ground,
        update: () => flushSync(() => setPill(next)),
      });
    }
    update(true);
    const onScroll = () => update(false);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header {...props(styles.header)}>
      <div ref={bar} {...props(styles.bar, pill ? styles.barPill : styles.barOpen)}>
        <span
          aria-hidden="true"
          ref={surface}
          {...props(styles.surface, pill && styles.surfacePill)}
        />
        <Link aria-label={m.app_name()} to="/" {...props(styles.home, pill && styles.homePill)}>
          <span ref={mark} {...props(styles.mark, pill && styles.markPill)}>
            <img
              alt={''}
              height={28}
              src="/icon.png"
              width={28}
              {...props(styles.icon, pill && styles.iconPill)}
            />
          </span>
          <span {...props(styles.name, pill && styles.hidden)} {...morphName('header-name')}>
            {m.app_name()}
          </span>
        </Link>
        <nav aria-label={m.header_nav_label()} {...props(styles.nav)}>
          {links.map((link) => (
            <a
              aria-current={link.current ? 'location' : undefined}
              href={link.href}
              key={link.name}
              {...props(styles.link, link.current && styles.current)}
              {...morphName(link.name)}
            >
              {link.label}
            </a>
          ))}
        </nav>
        <span {...props(styles.end)}>
          {release === null ? null : (
            <span {...props(styles.primary)} {...morphName('header-primary')}>
              <DownloadButton placement="header" release={release} size="compact">
                <WithAppleMark>{m.header_download()}</WithAppleMark>
              </DownloadButton>
            </span>
          )}
        </span>
        <SiteMenu anchor={bar} links={links} morph="header-menu" release={release} />
      </div>
    </header>
  );
}
