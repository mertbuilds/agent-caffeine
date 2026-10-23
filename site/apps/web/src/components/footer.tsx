import {
  breakpoints,
  colors,
  fontWeight,
  motion,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link } from '@tanstack/react-router';
import type { ReactNode } from 'react';
import { getPosts } from '../lib/blog.ts';
import { PORTAL_URL } from '../lib/pricing.ts';
import { CONTACT_EMAIL, MERTBUILDS_URL } from '../lib/site.ts';
import { m } from '../paraglide/messages.js';
import { ThemeSwitch } from './theme-switch.tsx';

// Up to the md breakpoint only, so it never competes with an md value: StyleX does not order overlapping min-width queries.
const SM_ONLY = '@media (min-width: 640px) and (max-width: 767.98px)';

const styles = create({
  bottom: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s4,
    justifyContent: 'space-between',
  },
  brand: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s3,
    gridColumn: { [breakpoints.md]: 'span 1', default: 'span 2', [SM_ONLY]: 'span 3' },
  },
  column: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
  },
  columns: {
    columnGap: spacing.s8,
    display: 'grid',
    gridAutoFlow: { [breakpoints.sm]: 'row', default: 'row dense' },
    gridTemplateColumns: {
      [breakpoints.md]: 'minmax(0, 1.4fr) repeat(3, minmax(0, 1fr))',
      default: 'repeat(2, minmax(0, 1fr))',
      [SM_ONLY]: 'repeat(3, minmax(0, 1fr))',
    },
    rowGap: spacing.s10,
  },
  footer: {
    borderTopColor: colors.border,
    borderTopStyle: 'solid',
    borderTopWidth: '1px',
    display: 'flex',
    flexDirection: 'column',
    fontSize: text.sm,
    gap: spacing.s14,
    lineHeight: text.smLeading,
    marginInline: 'auto',
    maxWidth: '1120px',
    paddingBottom: spacing.s10,
    paddingTop: { [breakpoints.md]: spacing.s16, default: spacing.s12 },
    width: '100%',
  },
  home: {
    alignItems: 'center',
    display: 'flex',
    fontSize: text.base,
    fontWeight: fontWeight.medium,
    gap: spacing.s2,
    lineHeight: text.baseLeading,
    textDecorationLine: 'none',
    width: 'fit-content',
  },
  link: {
    color: { ':hover': colors.fg, default: colors.muted },
    textDecorationLine: 'none',
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      '@media (prefers-reduced-motion: reduce)': 'none',
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
    },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  list: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s3,
  },
  muted: {
    color: colors.muted,
  },
  outbound: {
    alignItems: 'center',
    display: 'inline-flex',
    gap: spacing.s1,
  },
  pretty: {
    textWrap: 'pretty',
  },
  read: {
    gridColumn: { [breakpoints.sm]: 'span 1', default: 'span 2' },
  },
  // Read by a screen reader, not drawn.
  srOnly: {
    borderWidth: 0,
    clip: 'rect(0, 0, 0, 0)',
    height: '1px',
    margin: '-1px',
    overflow: 'hidden',
    padding: 0,
    position: 'absolute',
    whiteSpace: 'nowrap',
    width: '1px',
  },
  tagline: {
    color: colors.muted,
    textWrap: 'pretty',
  },
});

function Column({
  children,
  title,
  wide = false,
}: {
  children: ReactNode;
  title: string;
  wide?: boolean;
}) {
  return (
    <nav aria-label={title} {...props(styles.column, wide && styles.read)}>
      <h2>{title}</h2>
      <ul {...props(styles.list)}>{children}</ul>
    </nav>
  );
}

function FooterLink({ children, href }: { children: ReactNode; href: string }) {
  return (
    <li>
      <a href={href} {...props(styles.link)}>
        {children}
      </a>
    </li>
  );
}

/** The name and what it does, three columns of links, and the maker with the theme switch under them. */
export function Footer() {
  return (
    <footer {...props(styles.footer)}>
      <div {...props(styles.columns)}>
        <div {...props(styles.brand)}>
          <Link to="/" {...props(styles.home)}>
            <img alt={''} height={28} src="/icon.png" width={28} />
            <span>{m.app_name()}</span>
          </Link>
          <p {...props(styles.tagline)}>{m.footer_tagline()}</p>
        </div>
        <Column title={m.footer_product()}>
          <FooterLink href="/#examples">{m.header_examples()}</FooterLink>
          <FooterLink href="/#agents">{m.header_agents()}</FooterLink>
          <FooterLink href="/#features">{m.header_features()}</FooterLink>
          <FooterLink href="/#demo">{m.header_demo()}</FooterLink>
          <FooterLink href="/#pricing">{m.header_pricing()}</FooterLink>
          <FooterLink href="/#faq">{m.header_faq()}</FooterLink>
          <li>
            <Link to="/compare" {...props(styles.link)}>
              {m.footer_compare()}
            </Link>
          </li>
          <li>
            <a
              href={PORTAL_URL}
              rel="noreferrer"
              target="_blank"
              {...props(styles.link, styles.outbound)}
            >
              {m.footer_purchases()}
              <svg
                aria-hidden="true"
                fill="none"
                height="8"
                stroke="currentColor"
                strokeWidth="1"
                viewBox="0 0 8 8"
                width="8"
              >
                <path d="M1.5 6.5l5-5M2.5 1.5h4v4" />
              </svg>
              <span {...props(styles.srOnly)}>{m.footer_new_tab()}</span>
            </a>
          </li>
        </Column>
        <Column title={m.footer_read()} wide>
          <li>
            <Link to="/blog" {...props(styles.link)}>
              {m.footer_blog()}
            </Link>
          </li>
          {getPosts().map((post) => (
            <li key={post.slug}>
              <Link
                params={{ slug: post.slug }}
                to="/blog/$slug"
                {...props(styles.link, styles.pretty)}
              >
                {post.title}
              </Link>
            </li>
          ))}
        </Column>
        <Column title={m.footer_legal()}>
          <li>
            <Link to="/privacy" {...props(styles.link)}>
              {m.footer_privacy()}
            </Link>
          </li>
          <li>
            <Link to="/terms" {...props(styles.link)}>
              {m.footer_terms()}
            </Link>
          </li>
          <FooterLink href={`mailto:${CONTACT_EMAIL}`}>{m.footer_contact()}</FooterLink>
        </Column>
      </div>
      <div {...props(styles.bottom)}>
        <p {...props(styles.muted)}>
          {m.footer_utility_before()} <a href={MERTBUILDS_URL}>{m.footer_utility_link()}</a>{' '}
          {m.footer_utility_after()}
        </p>
        <ThemeSwitch />
      </div>
    </footer>
  );
}
