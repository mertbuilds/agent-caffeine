import { spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { createFileRoute } from '@tanstack/react-router';
import { CompareSources, CompareTable } from '../components/compare-table.tsx';
import { Footer } from '../components/footer.tsx';
import { page } from '../components/page.ts';
import { Rich } from '../components/rich.tsx';
import { formatDate } from '../lib/blog.ts';
import { CHECKED_ON, OURS, tools } from '../lib/compare.ts';
import type { ToolId } from '../lib/compare.ts';
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PRICE, dollars } from '../lib/pricing.ts';
import { AUTHOR, ORGANIZATION, pageHead } from '../lib/seo.ts';
import { SITE_URL } from '../lib/site.ts';
import { m } from '../paraglide/messages.js';

export const Route = createFileRoute('/compare')({
  component: ComparePage,
  head: () => {
    const title = m.compare_meta_title();
    const description = m.compare_meta_description();
    return pageHead({
      description,
      extra: [
        { content: CHECKED_ON, property: 'article:modified_time' },
        {
          'script:ld+json': {
            '@context': 'https://schema.org',
            '@type': 'WebPage',
            author: AUTHOR,
            dateModified: CHECKED_ON,
            description,
            name: title,
            publisher: ORGANIZATION,
            url: `${SITE_URL}/compare`,
          },
        },
      ],
      path: '/compare',
      title,
      type: 'article',
    });
  },
});

/** What each tool is good at and when to pick it, from the same pages as the table. */
const RIVALS: Record<Exclude<ToolId, 'ours'>, ReadonlyArray<() => string>> = {
  adrafinil: [
    m.compare_adrafinil_1,
    m.compare_adrafinil_2,
    m.compare_adrafinil_3,
    m.compare_adrafinil_4,
  ],
  amphetamine: [m.compare_amphetamine_1, m.compare_amphetamine_2, m.compare_amphetamine_3],
  clamshell: [m.compare_clamshell_1, m.compare_clamshell_2, m.compare_clamshell_3],
  holdmylid: [m.compare_holdmylid_1, m.compare_holdmylid_2, m.compare_holdmylid_3],
  lidrun: [m.compare_lidrun_1, m.compare_lidrun_2, m.compare_lidrun_3],
};

const styles = create({
  table: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
    marginInline: 'auto',
    maxWidth: '1120px',
    minWidth: 0,
    width: '100%',
  },
});

function ComparePage() {
  return (
    <main id="main" {...props(page.main)}>
      <header {...props(page.column, page.header)}>
        <h1 {...props(page.title)}>{m.compare_page_title()}</h1>
        <p {...props(page.lead)}>{`${m.compare_lead()}.`}</p>
        <p {...props(page.meta)}>
          {m.compare_checked_on()} <time dateTime={CHECKED_ON}>{formatDate(CHECKED_ON)}</time>
        </p>
      </header>
      <section aria-label={m.compare_table_region()} {...props(styles.table)}>
        <CompareTable />
        <CompareSources />
      </section>
      <article {...props(page.column)}>
        <div className="article">
          <div>
            <h2>{m.compare_price_heading()}</h2>
            <p>
              {LAUNCH_PRICE_ACTIVE
                ? m.compare_price_text_launch({
                    full: dollars(FULL_PRICE),
                    macs: MACS,
                    price: PRICE,
                  })
                : m.compare_price_text({ macs: MACS, price: PRICE })}
            </p>
            <p>{m.compare_together()}</p>
            {tools()
              .filter((tool) => tool.id !== OURS)
              .map((tool) => (
                <section id={tool.id} key={tool.id}>
                  <h2>{tool.name}</h2>
                  {(tool.id === 'ours' ? [] : RIVALS[tool.id])
                    .map((paragraph) => paragraph())
                    .map((paragraph) => (
                      <p key={paragraph}>
                        <Rich text={paragraph} />
                      </p>
                    ))}
                  <p>
                    {m.compare_sources_label()}{' '}
                    {tool.sources.map((source, index) => (
                      <span key={source.url}>
                        {index > 0 ? ', ' : null}
                        <a href={source.url} rel="noreferrer">
                          {source.label}
                        </a>
                      </span>
                    ))}
                    {'.'}
                  </p>
                </section>
              ))}
            <h2>{m.compare_caffeinate_heading()}</h2>
            <p>
              <Rich text={m.compare_caffeinate_text()} />
            </p>
          </div>
        </div>
      </article>
      <Footer />
    </main>
  );
}
