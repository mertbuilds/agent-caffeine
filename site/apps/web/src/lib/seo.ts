import { getPosts } from './blog.ts';
import { CHECKED_ON } from './compare.ts';
import { DOWNLOAD_PATH } from './download.ts';
import { SITE_URL } from './site.ts';

export const AUTHOR = { '@type': 'Person', name: 'Mert Duzgun', url: 'https://mertbuilds.com' };

export const ORGANIZATION = {
  '@type': 'Organization',
  logo: `${SITE_URL}/icon.png`,
  name: 'Agent Caffeine',
  url: SITE_URL,
};

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
