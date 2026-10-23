import { describe, expect, it } from 'vitest';
import { checkoutUrlWith, parseUtm, utmFrom } from './attribution.ts';

const LINK = 'https://buy.polar.sh/polar_cl_abc';

describe('utmFrom', () => {
  it('gives the three tags of a link from the app', () => {
    expect(utmFrom('?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=help')).toEqual({
      utm_campaign: 'help',
      utm_medium: 'app',
      utm_source: 'agent-caffeine-app',
    });
  });

  it('leaves out other parameters and empty tags', () => {
    expect(utmFrom('?ref=x&utm_source=&utm_term=%20&email=a%40b.c')).toEqual({});
    expect(utmFrom('')).toEqual({});
  });

  it('cuts a tag at 100 characters', () => {
    expect(utmFrom(`?utm_source=${'a'.repeat(300)}`).utm_source).toHaveLength(100);
  });
});

describe('checkoutUrlWith', () => {
  it("carries the visitor's tags", () => {
    expect(
      checkoutUrlWith(LINK, {
        utm_campaign: 'launch week',
        utm_medium: 'ad',
        utm_source: 'claudemarketplaces',
      }),
    ).toBe(`${LINK}?utm_source=claudemarketplaces&utm_medium=ad&utm_campaign=launch+week`);
  });

  it("counts a visitor with no source as the site's own", () => {
    expect(checkoutUrlWith(LINK, {})).toBe(`${LINK}?utm_source=caffeinagent.com`);
    expect(checkoutUrlWith(LINK, { utm_medium: 'ad' })).toBe(`${LINK}?utm_source=caffeinagent.com`);
  });

  it("keeps a link's own parameters, and a tag of the visitor replaces the link's", () => {
    expect(checkoutUrlWith(`${LINK}?discount_code=EARLY&utm_source=old`, { utm_source: 'x' })).toBe(
      `${LINK}?discount_code=EARLY&utm_source=x`,
    );
  });

  it('gives back a link that cannot be read as it is', () => {
    expect(checkoutUrlWith('#pricing', { utm_source: 'x' })).toBe('#pricing');
  });
});

describe('parseUtm', () => {
  it('reads stored tags back, and drops anything else in the store', () => {
    expect(parseUtm('{"utm_source":"x","other":"y","utm_medium":3}')).toEqual({ utm_source: 'x' });
    expect(parseUtm('{}')).toEqual({});
    expect(parseUtm(null)).toBeNull();
    expect(parseUtm('not json')).toBeNull();
    expect(parseUtm('"text"')).toBeNull();
  });
});
