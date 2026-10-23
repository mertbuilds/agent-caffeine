import { describe, expect, it } from 'vitest';
import { MERTBUILDS_URL, ownLink } from './site.ts';

describe('ownLink', () => {
  it('tags a link to an own site with the three tags, with where it sits', () => {
    const link = new URL(ownLink('https://mertbuilds.com/', 'footer'));
    expect(link.origin).toBe('https://mertbuilds.com');
    expect(link.searchParams.get('utm_source')).toBe('caffeinagent.com');
    expect(link.searchParams.get('utm_medium')).toBe('referral');
    expect(link.searchParams.get('utm_campaign')).toBe('footer');
  });

  it('replaces tags already on the link instead of doubling them', () => {
    const link = new URL(ownLink('https://mertbuilds.com/?utm_campaign=old&x=1', 'header'));
    expect(link.searchParams.getAll('utm_campaign')).toEqual(['header']);
    expect(link.searchParams.get('x')).toBe('1');
  });

  it('tags the footer mertbuilds link for the footer', () => {
    expect(MERTBUILDS_URL).toBe(
      'https://mertbuilds.com/?utm_source=caffeinagent.com&utm_medium=referral&utm_campaign=footer',
    );
  });
});
