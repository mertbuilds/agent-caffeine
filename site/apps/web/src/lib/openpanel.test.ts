import { afterEach, describe, expect, it } from 'vitest';
import { loadOpenPanel } from './openpanel.ts';

afterEach(() => {
  Reflect.deleteProperty(window, 'op');
  for (const script of document.head.querySelectorAll('script')) {
    script.remove();
  }
});

describe('loadOpenPanel', () => {
  it('queues the init for the script and loads it through the proxy', () => {
    loadOpenPanel('client');
    expect(window.op).toBeTypeOf('function');
    const queue: unknown = Reflect.get(window.op ?? {}, 'q');
    expect(queue).toEqual([
      [
        'init',
        expect.objectContaining({ apiUrl: '/api/op', clientId: 'client', trackScreenViews: true }),
      ],
    ]);
    expect(document.head.querySelector('script')?.getAttribute('src')).toBe('/api/op/op1.js');
  });

  it('keeps calls made before it in the same queue', () => {
    loadOpenPanel('client');
    window.op?.('track', 'faq_open', { id: 'price' });
    const queue: unknown = Reflect.get(window.op ?? {}, 'q');
    expect(queue).toHaveLength(2);
  });
});
