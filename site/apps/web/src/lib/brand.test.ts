import { describe, expect, it } from 'vitest';
import { siteText } from '../test/site-text.ts';

/**
 * The bundle of the app is `Agent Caffeine.app` from 1.0.2. It was
 * `agent caffeine.app` in 1.0.0 and 1.0.1, and an update keeps that name,
 * so a text may still name the earlier bundle.
 */
const MACHINE_NAMES = ['agent caffeine.app'];

function lowercaseBrand(line: string): boolean {
  const rest = MACHINE_NAMES.reduce((text, name) => text.replaceAll(name, ''), line).replaceAll(
    'Agent Caffeine',
    '',
  );
  return /agent\s+caffeine/iu.test(rest);
}

describe('the brand', () => {
  it('is written Agent Caffeine in every text people read', () => {
    expect(siteText.length).toBeGreaterThan(50);
    const wrong = siteText.flatMap(([file, text]) =>
      text
        .split('\n')
        .flatMap((line, index) =>
          lowercaseBrand(line) ? [`${file}:${index + 1}: ${line.trim()}`] : [],
        ),
    );
    expect(wrong).toEqual([]);
  });

  it('lets both names of the bundle pass, and not the lowercase brand', () => {
    expect(
      lowercaseBrand('ls /Applications/Agent Caffeine.app /Applications/agent caffeine.app'),
    ).toBe(false);
    expect(lowercaseBrand('open agent caffeine from Applications')).toBe(true);
  });
});
