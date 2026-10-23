import { breakpoints, spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { createFileRoute } from '@tanstack/react-router';
import { Footer } from '../components/footer.tsx';
import { homeStructuredData } from '../lib/seo.ts';
import { Agents } from '../sections/agents.tsx';
import { Compare } from '../sections/compare.tsx';
import { Demo } from '../sections/demo.tsx';
import { Examples } from '../sections/examples.tsx';
import { Faq } from '../sections/faq.tsx';
import { Guides } from '../sections/guides.tsx';
import { Hero } from '../sections/hero.tsx';
import { Pricing } from '../sections/pricing.tsx';
import { SleepScenes } from '../sections/sleep-scenes.tsx';
import { SmallThings } from '../sections/small-things.tsx';

export const Route = createFileRoute('/')({
  component: Home,
  // Whether there is a download, and so a free trial, from the root route's release.
  loader: async ({ parentMatchPromise }) => ({
    trial: (await parentMatchPromise).loaderData != null,
  }),
  // oxlint-disable-next-line perfectionist/sort-objects -- head after loader, or TypeScript cannot infer loaderData for head
  head: ({ loaderData }) => ({
    links: [{ href: 'https://caffeinagent.com/', rel: 'canonical' }],
    meta: [{ content: 'https://caffeinagent.com/', property: 'og:url' }],
    scripts: [
      {
        // `<` escaped, so the JSON cannot close the tag.
        children: JSON.stringify(homeStructuredData(loaderData?.trial ?? false)).replaceAll(
          '<',
          String.raw`\u003c`,
        ),
        type: 'application/ld+json',
      },
    ],
  }),
});

const styles = create({
  main: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s24,
    isolation: 'isolate',
    minHeight: '100vh',
    overflowX: 'clip',
    paddingInline: { [breakpoints.md]: spacing.s6, default: spacing.s4 },
    paddingTop: spacing.s14,
    position: 'relative',
  },
});

/** The home page: one file per section under src/sections, in the order they stand. */
function Home() {
  return (
    <main id="main" {...props(styles.main)}>
      <Hero />
      <Examples />
      <Agents />
      <SleepScenes />
      <SmallThings />
      <Demo />
      <Compare />
      <Pricing />
      <Faq />
      <Guides />
      <Footer />
    </main>
  );
}
