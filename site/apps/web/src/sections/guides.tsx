import { colors, fontWeight, leading, motion, spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link } from '@tanstack/react-router';
import { getPosts } from '../lib/blog.ts';
import { m } from '../paraglide/messages.js';

const styles = create({
  item: {
    borderTopColor: colors.border,
    borderTopStyle: { ':first-child': 'none', default: 'solid' },
    borderTopWidth: '1px',
  },
  link: {
    color: { ':hover': colors.muted, default: null },
    display: 'block',
    lineHeight: leading.normal,
    paddingBlock: spacing.s4,
    textDecorationLine: 'none',
    textWrap: 'pretty',
    transitionDuration: motion.durationQuick,
    transitionProperty: { '@media (prefers-reduced-motion: reduce)': 'none', default: 'color' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  section: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s6,
    marginInline: 'auto',
    maxWidth: '640px',
    width: '100%',
  },
  title: {
    fontSize: '1.75rem',
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.2,
    textWrap: 'balance',
  },
});

/** Every guide of the blog, one click from the home page. */
export function Guides() {
  return (
    <section aria-labelledby="guides" {...props(styles.section)}>
      <h2 id="guides" {...props(styles.title)}>
        {m.guides_title()}
      </h2>
      <ul>
        {getPosts().map((post) => (
          <li key={post.slug} {...props(styles.item)}>
            <Link params={{ slug: post.slug }} to="/blog/$slug" {...props(styles.link)}>
              {post.title}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
