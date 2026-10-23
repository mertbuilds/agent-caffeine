import { breakpoints, colors, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { createFileRoute, Link, notFound } from '@tanstack/react-router';
import { Footer } from '../../components/footer.tsx';
import { page } from '../../components/page.ts';
import { pill } from '../../components/pill.ts';
import { formatDate, getPost } from '../../lib/blog.ts';
import { DOWNLOAD_PATH } from '../../lib/download.ts';
import { getLatestRelease } from '../../lib/latest-release.functions.ts';
import { CHECKOUT_URL, MACS, PRICE, PRICE_NOW } from '../../lib/pricing.ts';
import { AUTHOR, ORGANIZATION, pageHead } from '../../lib/seo.ts';
import { ownLink, SITE_URL } from '../../lib/site.ts';
import { track } from '../../lib/track.ts';
import { m } from '../../paraglide/messages.js';

export const Route = createFileRoute('/blog/$slug')({
  component: BlogPost,
  loader: async ({ params }) => {
    const [post, release] = await Promise.all([getPost(params.slug), getLatestRelease()]);
    if (post === undefined) {
      throw notFound();
    }
    return { post, release };
  },
  // oxlint-disable-next-line perfectionist/sort-objects -- head after loader, or TypeScript cannot infer loaderData for head
  head: ({ loaderData }) => {
    if (loaderData === undefined) {
      return { meta: [{ title: m.notfound_meta_title() }] };
    }
    const { post } = loaderData;
    const url = `${SITE_URL}/blog/${post.slug}`;
    return pageHead({
      description: post.description,
      extra: [
        { content: post.date, property: 'article:published_time' },
        { content: post.updated, property: 'article:modified_time' },
        { content: AUTHOR.url, property: 'article:author' },
        {
          'script:ld+json': {
            '@context': 'https://schema.org',
            '@graph': [
              {
                '@type': 'BlogPosting',
                author: AUTHOR,
                dateModified: post.updated,
                datePublished: post.date,
                description: post.description,
                headline: post.title,
                image: `${SITE_URL}/og.png`,
                mainEntityOfPage: { '@id': url, '@type': 'WebPage' },
                publisher: ORGANIZATION,
                url,
              },
              ...(post.faq.length === 0
                ? []
                : [
                    {
                      '@type': 'FAQPage',
                      mainEntity: post.faq.map((item) => ({
                        '@type': 'Question',
                        acceptedAnswer: { '@type': 'Answer', text: item.text },
                        name: item.q,
                      })),
                    },
                  ]),
            ],
          },
        },
      ],
      path: `/blog/${post.slug}`,
      title: post.title,
      type: 'article',
    });
  },
});

const AUTHOR_LINK = ownLink('https://mertbuilds.com/', 'blog');

function trackBuy() {
  track('buy_click', { placement: 'blog', price: PRICE_NOW });
}

const styles = create({
  actions: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: spacing.s4,
  },
  aside: {
    alignItems: { [breakpoints.sm]: 'center', default: 'flex-start' },
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: radius.lg,
    borderStyle: 'solid',
    borderWidth: '1px',
    display: 'flex',
    flexDirection: { [breakpoints.sm]: 'row', default: 'column' },
    gap: spacing.s5,
    justifyContent: { [breakpoints.sm]: 'space-between', default: null },
    paddingBlock: spacing.s8,
    paddingInline: spacing.s6,
  },
  asideText: {
    lineHeight: 1.625,
    textWrap: 'pretty',
  },
  back: {
    color: { ':hover': colors.fg, default: colors.muted },
    fontSize: text.sm,
    lineHeight: text.smLeading,
    textDecorationLine: 'none',
    width: 'fit-content',
  },
  textLink: {
    color: { ':hover': colors.fg, default: colors.muted },
    flexShrink: 0,
    fontSize: text.sm,
    lineHeight: text.smLeading,
    textDecorationLine: 'none',
    transitionDuration: motion.durationQuick,
    transitionProperty: { '@media (prefers-reduced-motion: reduce)': 'none', default: 'color' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
});

function BlogPost() {
  const { post, release } = Route.useLoaderData();
  return (
    <main id="main" {...props(page.main)}>
      <article {...props(page.column)}>
        <header {...props(page.header)}>
          <Link to="/blog" {...props(styles.back)}>
            {m.blog_title()}
          </Link>
          <h1 {...props(page.title)}>{post.title}</h1>
          <p {...props(page.meta)}>
            <time dateTime={post.date}>{formatDate(post.date)}</time> · {m.blog_by()}{' '}
            <a href={AUTHOR_LINK}>{m.blog_author()}</a>
          </p>
        </header>
        <div className="article">
          <div dangerouslySetInnerHTML={{ __html: post.html[0] }} />
          {post.faq.length === 0 ? null : (
            <section>
              <h2>{m.blog_questions()}</h2>
              {post.faq.map((item) => (
                <div key={item.q}>
                  <h3>{item.q}</h3>
                  <p dangerouslySetInnerHTML={{ __html: item.html }} />
                </div>
              ))}
            </section>
          )}
          <div dangerouslySetInnerHTML={{ __html: post.html[1] }} />
        </div>
        <aside {...props(styles.aside)}>
          <p {...props(styles.asideText)}>
            {m.blog_aside_lead()}{' '}
            {release === null
              ? m.blog_aside_buy_only({ macs: MACS, price: PRICE })
              : m.blog_aside_trial({ price: PRICE })}
          </p>
          {release === null ? (
            <a href={CHECKOUT_URL} onClick={trackBuy} {...props(pill.base, pill.ink, pill.small)}>
              {m.blog_buy({ price: PRICE })}
            </a>
          ) : (
            <div {...props(styles.actions)}>
              <a
                href={DOWNLOAD_PATH}
                onClick={() => track('download_click', { placement: 'blog' })}
                {...props(pill.base, pill.ink, pill.small)}
              >
                {m.blog_try_free()}
              </a>
              <a href={CHECKOUT_URL} onClick={trackBuy} {...props(styles.textLink)}>
                {m.blog_buy({ price: PRICE })}
              </a>
            </div>
          )}
        </aside>
      </article>
      <Footer />
    </main>
  );
}
