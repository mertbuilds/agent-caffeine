import { colors, fontWeight, leading, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, defaultMarker, props, when } from '@stylexjs/stylex';
import { createFileRoute, Link } from '@tanstack/react-router';
import { Footer } from '../../components/footer.tsx';
import { page } from '../../components/page.ts';
import { formatDate, getPosts } from '../../lib/blog.ts';
import { pageHead } from '../../lib/seo.ts';
import { m } from '../../paraglide/messages.js';

export const Route = createFileRoute('/blog/')({
  component: BlogIndex,
  head: () =>
    pageHead({
      description: m.blog_meta_description(),
      path: '/blog',
      title: m.blog_meta_title(),
    }),
});

const styles = create({
  date: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  description: {
    color: colors.muted,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  item: {
    borderTopColor: colors.border,
    borderTopStyle: { ':first-child': 'none', default: 'solid' },
    borderTopWidth: '1px',
    paddingBottom: spacing.s6,
    paddingTop: { ':first-child': 0, default: spacing.s6 },
  },
  link: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s2,
    textDecorationLine: 'none',
  },
  main: {
    gap: spacing.s16,
    paddingTop: '7.5rem',
  },
  postTitle: {
    fontSize: text.xl,
    fontWeight: fontWeight.medium,
    lineHeight: leading.snug,
    textDecorationLine: { default: null, [when.ancestor(':hover')]: 'underline' },
    textWrap: 'pretty',
  },
  section: {
    flex: 1,
  },
  title: {
    fontSize: '2rem',
  },
});

/** Every post, newest first, each with what it covers and its day. */
function BlogIndex() {
  return (
    <main id="main" {...props(page.main, styles.main)}>
      <section {...props(page.column, styles.section)}>
        <h1 {...props(page.title, styles.title)}>{m.blog_title()}</h1>
        <ul>
          {getPosts().map((post) => (
            <li key={post.slug} {...props(styles.item)}>
              <Link
                params={{ slug: post.slug }}
                to="/blog/$slug"
                {...props(defaultMarker(), styles.link)}
              >
                <span {...props(styles.postTitle)}>{post.title}</span>
                <span {...props(styles.description)}>{post.description}</span>
                <time dateTime={post.date} {...props(styles.date)}>
                  {formatDate(post.date)}
                </time>
              </Link>
            </li>
          ))}
        </ul>
      </section>
      <Footer />
    </main>
  );
}
