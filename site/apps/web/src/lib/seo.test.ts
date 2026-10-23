import { describe, expect, it } from 'vitest';
import { getPosts } from './blog.ts';
import { pageHead, robotsTxt, sitemapXml } from './seo.ts';

describe('robotsTxt', () => {
  it('keeps the picture page, the download and the analytics proxy out, and names the sitemap', () => {
    expect(robotsTxt()).toBe(
      [
        'User-Agent: *',
        'Allow: /',
        'Disallow: /og-image',
        'Disallow: /download',
        'Disallow: /api/',
        '',
        'Sitemap: https://caffeinagent.com/sitemap.xml',
        '',
      ].join('\n'),
    );
  });
});

describe('sitemapXml', () => {
  it('lists home, compare, the blog, every post and the legal pages on the live origin', () => {
    const xml = sitemapXml();
    expect(xml.startsWith('<?xml version="1.0" encoding="UTF-8"?>\n<urlset')).toBe(true);
    expect([...xml.matchAll(/<loc>([^<]+)<\/loc>/gu)].map((match) => match[1])).toEqual([
      'https://caffeinagent.com',
      'https://caffeinagent.com/compare',
      'https://caffeinagent.com/blog',
      ...getPosts().map((post) => `https://caffeinagent.com/blog/${post.slug}`),
      'https://caffeinagent.com/privacy',
      'https://caffeinagent.com/terms',
    ]);
    expect(xml).toContain(
      '<loc>https://caffeinagent.com/compare</loc>\n<lastmod>2026-10-08</lastmod>',
    );
  });
});

describe('pageHead', () => {
  it('names the page, its canonical address and its share tags', () => {
    const head = pageHead({ description: 'D', path: '/compare', title: 'T', type: 'article' });
    expect(head.links).toEqual([{ href: 'https://caffeinagent.com/compare', rel: 'canonical' }]);
    expect(head.meta).toContainEqual({ title: 'T' });
    expect(head.meta).toContainEqual({ content: 'article', property: 'og:type' });
    expect(head.meta).toContainEqual({
      content: 'https://caffeinagent.com/compare',
      property: 'og:url',
    });
  });
});
