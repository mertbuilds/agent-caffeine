import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { applyTheme, readTheme, subscribeTheme, THEME_SCRIPT } from './theme.ts';

// A store of our own: Node 25 and later shadow jsdom's localStorage with one of its own, unset without a file.
beforeEach(() => {
  const kept = new Map<string, string>();
  vi.stubGlobal('localStorage', {
    getItem: (key: string) => kept.get(key) ?? null,
    removeItem: (key: string) => kept.delete(key),
    setItem: (key: string, value: string) => kept.set(key, value),
  });
});

afterEach(() => {
  delete document.documentElement.dataset['theme'];
  vi.unstubAllGlobals();
});

describe('theme', () => {
  it('keeps a picked theme on <html> and in storage, and the system one as neither', () => {
    applyTheme('dark');
    expect(document.documentElement.dataset['theme']).toBe('dark');
    expect(localStorage.getItem('theme')).toBe('dark');
    expect(readTheme()).toBe('dark');
    applyTheme('system');
    expect(document.documentElement.dataset['theme']).toBeUndefined();
    expect(localStorage.getItem('theme')).toBeNull();
    expect(readTheme()).toBe('system');
  });

  it('tells every listener of a change, until it leaves', () => {
    let heard = 0;
    const leave = subscribeTheme(() => {
      heard += 1;
    });
    applyTheme('light');
    leave();
    applyTheme('dark');
    expect(heard).toBe(1);
  });

  it('puts the kept theme back before the first paint, and nothing else', () => {
    localStorage.setItem('theme', 'light');
    new Function(THEME_SCRIPT)();
    expect(document.documentElement.dataset['theme']).toBe('light');
    delete document.documentElement.dataset['theme'];
    localStorage.setItem('theme', 'blue');
    new Function(THEME_SCRIPT)();
    expect(document.documentElement.dataset['theme']).toBeUndefined();
  });
});
