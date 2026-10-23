import { describe, expect, it } from 'vitest';
import {
  BATTERY_FLOOR,
  CHECKED_ON,
  OURS,
  AGENTS_MORE_THAN,
  isText,
  rows,
  tools,
} from './compare.ts';
import { MACS, PRICE } from './pricing.ts';

function ours(id: string) {
  return rows().find((row) => row.id === id)?.cells[OURS];
}

describe('the comparison', () => {
  it('was checked on a real day', () => {
    expect(CHECKED_ON).toMatch(/^\d{4}-\d{2}-\d{2}$/u);
    expect(new Date(`${CHECKED_ON}T00:00:00Z`).toISOString().slice(0, 10)).toBe(CHECKED_ON);
  });

  it('has a cell for every tool in every row, and a source for every claim about another tool', () => {
    const all = rows();
    expect(new Set(all.map((row) => row.id)).size).toBe(all.length);
    for (const tool of tools()) {
      for (const source of tool.sources) {
        expect(URL.canParse(source.url) && source.url.startsWith('https://'), source.url).toBe(
          true,
        );
      }
      for (const row of all) {
        const cell = row.cells[tool.id];
        const claim = isText(cell) || cell.value !== 'unstated' || cell.note !== undefined;
        if (tool.id !== OURS && claim) {
          expect(tool.sources.length, `${tool.name} needs a source for ${row.id}`).toBeGreaterThan(
            0,
          );
        }
      }
    }
  });

  it('says in our cells what the rest of the site says', () => {
    expect(rows()[0]?.id).toBe('price');
    const price = ours('price');
    expect(price !== undefined && isText(price) ? price.text : null).toBe(
      `${PRICE} once for ${MACS} Macs`,
    );
    expect(ours('works')?.note).toContain(`more than ${AGENTS_MORE_THAN} agents`);
    expect(ours('battery-stop')?.note).toContain(`${BATTERY_FLOOR}%`);
  });

  it('has no em dash in any cell', () => {
    expect(JSON.stringify(rows())).not.toContain(String.fromCodePoint(0x20_14));
  });
});
