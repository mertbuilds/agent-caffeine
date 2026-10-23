import { describe, expect, it } from 'vitest';
import { formatDate, getPost, getPosts } from './blog.ts';
import { PRICE } from './pricing.ts';

describe('getPosts', () => {
  it('lists every article in content/blog, newest first, with its dates as plain days', () => {
    const posts = getPosts();
    expect(posts.map((post) => post.slug).toSorted()).toEqual([
      'amphetamine-mac',
      'caffeinate-mac',
      'caffeine-mac',
      'keep-mac-awake-lid-closed',
      'keep-mac-awake-while-command-runs',
      'stop-mac-from-sleeping',
    ]);
    const dates = posts.map((post) => post.date);
    expect(dates).toEqual(dates.toSorted().toReversed());
    for (const post of posts) {
      expect(post.date).toMatch(/^\d{4}-\d{2}-\d{2}$/u);
      expect(post.updated >= post.date, post.slug).toBe(true);
    }
  });
});

describe('getPost', () => {
  it('renders the body, the questions and the price', async () => {
    const post = await getPost('caffeinate-mac');
    expect(post?.title).toBe('The caffeinate command on Mac: every option, with examples');
    expect(post?.faq[0]?.q).toBe('Does caffeinate work on a Mac?');
    expect(post?.faq[0]?.html).toContain('<code>caffeinate</code>');
    expect(post?.faq[0]?.text).not.toContain('<');
    const html = post?.html.join('') ?? '';
    expect(html).toContain('<h2');
    expect(html).not.toContain('{{price}}');
    expect(html).toContain(PRICE);
  });

  it('wraps a table in a box that scrolls', async () => {
    const bodies = await Promise.all(getPosts().map((post) => getPost(post.slug)));
    const html = bodies.map((post) => post?.html.join('') ?? '').join('');
    expect(html).toContain(
      '<div class="table-scroll" tabindex="0" role="region" aria-label="Table"><table>',
    );
  });

  it('is undefined for a slug no article has', async () => {
    expect(await getPost('nope')).toBeUndefined();
  });
});

describe('formatDate', () => {
  it('writes a day the way the page shows it', () => {
    expect(formatDate('2026-10-08')).toBe('October 8, 2026');
  });
});
