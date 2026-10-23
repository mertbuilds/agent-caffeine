import { agentsMoreThan } from './agents.ts';
import { getPosts } from './blog.ts';
import { CHECKED_ON } from './compare.ts';
import { DOWNLOAD_PATH } from './download.ts';
import { faqPage } from './faq.tsx';
import { MACS, PRICE, PRICE_NOW } from './pricing.ts';
import { SITE_URL } from './site.ts';

export const AUTHOR = { '@type': 'Person', name: 'Mert Duzgun', url: 'https://mertbuilds.com' };

export const ORGANIZATION = {
  '@type': 'Organization',
  logo: `${SITE_URL}/icon.png`,
  name: 'Agent Caffeine',
  url: SITE_URL,
};

/** The home page's structured data. `trial` is whether there is a download, and so a free trial a reader can start. */
export function homeStructuredData(trial: boolean) {
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'SoftwareApplication',
        applicationCategory: 'UtilitiesApplication',
        description: `A macOS menu bar app that keeps the Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are idle or wait for you. Detects Claude Code, Codex, opencode and more than ${agentsMoreThan} AI coding agents.${
          trial
            ? ` Free to download, with every feature for 7 days. After that it needs a license key, ${PRICE} once for up to ${MACS} Macs.`
            : ''
        }`,
        featureList: [
          'Keeps the Mac awake while an AI coding agent works, also with the lid closed',
          'Lets the Mac sleep when agents are idle or wait for you',
          'Dims the built-in display as the lid closes and keeps it dark while the lid is closed',
          'Plays one short sound when the lid closes and the Mac stays awake',
          'Pause for 30 minutes, 1 hour or until tomorrow',
          'Stay reachable for 1, 2 or 4 hours, so a message from your phone reaches your agent',
          'Notifications when an agent waits for your answer or finishes',
          'Battery bar in the menu, and sleep at a battery level you set',
          'Command line tool and MCP server: a script, a long job or an agent can ask for the Mac to stay awake',
          'Keyboard shortcuts that work in every app',
          'The menu bar icon can be hidden',
        ],
        image: `${SITE_URL}/icon.png`,
        name: 'Agent Caffeine',
        offers: {
          '@type': 'Offer',
          name: `Agent Caffeine for up to ${MACS} Macs`,
          price: String(PRICE_NOW),
          priceCurrency: 'USD',
          url: SITE_URL,
        },
        operatingSystem: 'macOS 13 or later',
        url: SITE_URL,
      },
      faqPage(),
      ORGANIZATION,
      { '@type': 'WebSite', name: 'Agent Caffeine', url: SITE_URL },
    ],
  };
}

export const PRIVACY_UPDATED = '2026-10-23';

export const TERMS_UPDATED = '2026-10-23';

type Meta = Record<string, unknown>;

/**
 * A page's own title, description, canonical link and share tags. The root
 * route gives every page the share picture; a child's tag of the same name or
 * property replaces the root's.
 */
export function pageHead({
  description,
  extra = [],
  path,
  title,
  type = 'website',
}: {
  description: string;
  extra?: Array<Meta>;
  path: string;
  title: string;
  type?: 'article' | 'website';
}) {
  const url = `${SITE_URL}${path}`;
  return {
    links: [{ href: url, rel: 'canonical' }],
    meta: [
      { title },
      { content: description, name: 'description' },
      { content: title, property: 'og:title' },
      { content: description, property: 'og:description' },
      { content: type, property: 'og:type' },
      { content: url, property: 'og:url' },
      { content: title, name: 'twitter:title' },
      { content: description, name: 'twitter:description' },
      ...extra,
    ],
  };
}

/** The dev-only picture page, the download redirect and the analytics proxy stay out of search. */
export function robotsTxt(): string {
  return [
    'User-Agent: *',
    'Allow: /',
    'Disallow: /og-image',
    `Disallow: ${DOWNLOAD_PATH}`,
    'Disallow: /api/',
    '',
    `Sitemap: ${SITE_URL}/sitemap.xml`,
    '',
  ].join('\n');
}

export function sitemapXml(): string {
  const posts = getPosts();
  const pages: Array<{ lastModified?: string | undefined; path: string }> = [
    { path: '' },
    { lastModified: CHECKED_ON, path: '/compare' },
    { lastModified: posts[0]?.updated, path: '/blog' },
    ...posts.map((post) => ({ lastModified: post.updated, path: `/blog/${post.slug}` })),
    { lastModified: PRIVACY_UPDATED, path: '/privacy' },
    { lastModified: TERMS_UPDATED, path: '/terms' },
  ];
  const urls = pages.map((page) =>
    [
      '<url>',
      `<loc>${SITE_URL}${page.path}</loc>`,
      ...(page.lastModified === undefined ? [] : [`<lastmod>${page.lastModified}</lastmod>`]),
      '</url>',
    ].join('\n'),
  );
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls,
    '</urlset>',
    '',
  ].join('\n');
}
