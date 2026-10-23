import { describe, expect, it } from 'vitest';
import { siteText } from '../test/site-text.ts';

/** The words of the free, open source app. None may come back into the site of the paid one. */
const FREE = {
  agpl: /\bAGPL\b/iu,
  free: /free and open source/iu,
  repo: /github\.com\/(mertbuilds|sponsors)/iu,
  support: /#support/u,
};

/** The files and messages that tell about other tools, which may be free and open source. */
function allowed(file: string, line: string): boolean {
  return (
    file === 'apps/web/src/lib/compare.ts' ||
    file === 'apps/web/src/routes/compare.tsx' ||
    file === 'THIRD_PARTY_NOTICES.md' ||
    file.startsWith('apps/web/content/blog/') ||
    (file === 'apps/web/messages/en.json' && /^\s*"compare_/u.test(line))
  );
}

function freeWords(file: string, text: string): Array<string> {
  return text
    .split('\n')
    .flatMap((line, index) =>
      allowed(file, line)
        ? []
        : (Object.keys(FREE) as Array<keyof typeof FREE>)
            .filter((word) => FREE[word].test(line))
            .map((word) => `${file}:${index + 1}: ${word}: ${line.trim()}`),
    );
}

describe('the paid site', () => {
  it('never calls the app free and open source, or links to its code or to support', () => {
    expect(siteText.length).toBeGreaterThan(50);
    expect(siteText.flatMap(([file, text]) => freeWords(file, text))).toEqual([]);
  });

  it('finds each word of the free app, and lets a page about other tools say them', () => {
    const hero = 'apps/web/src/sections/hero.tsx';
    const footer = 'apps/web/src/components/footer.tsx';
    const messages = 'apps/web/messages/en.json';
    expect(freeWords(hero, 'Free and open source\nUnder the AGPL-3.0')).toHaveLength(2);
    expect(
      freeWords('apps/web/src/lib/faq.tsx', 'https://github.com/mertbuilds/agent-caffeine'),
    ).toHaveLength(1);
    expect(freeWords(footer, 'https://github.com/sponsors/mertbuilds')).toHaveLength(1);
    expect(freeWords(footer, '<a href="/#support">')).toHaveLength(1);
    expect(freeWords(messages, '  "hero_title": "Free and open source",')).toHaveLength(1);
    expect(
      freeWords(messages, '  "compare_adrafinil_1": "Adrafinil is free and open source (MIT).",'),
    ).toHaveLength(0);
    expect(
      freeWords('apps/web/src/routes/compare.tsx', 'Adrafinil is free and open source (MIT)'),
    ).toHaveLength(0);
    expect(freeWords('apps/web/content/blog/caffeine-mac.md', 'Free and open source')).toHaveLength(
      0,
    );
    expect(freeWords(hero, 'Free for 7 days, then $9 once')).toHaveLength(0);
  });
});
