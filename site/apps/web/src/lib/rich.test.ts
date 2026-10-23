import { describe, expect, it } from 'vitest';
import { richParts } from './rich.ts';

describe('richParts', () => {
  it('cuts a message at its code and its links', () => {
    expect(richParts('Run `caffeinate` or read [the guide](/blog/caffeinate-mac).')).toEqual([
      { kind: 'text', text: 'Run ' },
      { kind: 'code', text: 'caffeinate' },
      { kind: 'text', text: ' or read ' },
      { href: '/blog/caffeinate-mac', kind: 'link', text: 'the guide' },
      { kind: 'text', text: '.' },
    ]);
  });

  it('leaves plain text whole', () => {
    expect(richParts('No marks here (none).')).toEqual([
      { kind: 'text', text: 'No marks here (none).' },
    ]);
  });

  it('reads a mail link', () => {
    expect(richParts('[hi@caffeinagent.com](mailto:hi@caffeinagent.com)')).toEqual([
      { href: 'mailto:hi@caffeinagent.com', kind: 'link', text: 'hi@caffeinagent.com' },
    ]);
  });
});
