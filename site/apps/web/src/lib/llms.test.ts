import { describe, expect, it } from 'vitest';
import { getPosts } from './blog.ts';
import { llmsTxt } from './llms.ts';
import { PRICE } from './pricing.ts';

describe('llmsTxt', () => {
  it('names the app, the price, the pages and every guide', () => {
    const text = llmsTxt();
    expect(text.startsWith('# Agent Caffeine\n\n> ')).toBe(true);
    expect(text).toContain(`then costs ${PRICE} once`);
    expect(text).toContain('- [Compare](https://caffeinagent.com/compare)');
    for (const post of getPosts()) {
      expect(text).toContain(`- [${post.title}](https://caffeinagent.com/blog/${post.slug}): `);
    }
    expect(text).not.toContain(String.fromCodePoint(0x20_14));
  });
});
