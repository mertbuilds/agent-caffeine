import { describe, expect, it } from 'vitest';
import { movedRedirect } from './redirects.ts';

describe('movedRedirect', () => {
  it('sends /support to the price for good', () => {
    const response = movedRedirect(new URL('https://caffeinagent.com/support'));
    expect(response?.status).toBe(301);
    expect(response?.headers.get('location')).toBe('https://caffeinagent.com/#pricing');
  });

  it('takes a trailing slash and keeps the host it was asked on', () => {
    const response = movedRedirect(new URL('http://localhost:3000/support/'));
    expect(response?.headers.get('location')).toBe('http://localhost:3000/#pricing');
  });

  it('leaves every other path to the app', () => {
    expect(movedRedirect(new URL('https://caffeinagent.com/'))).toBeNull();
    expect(movedRedirect(new URL('https://caffeinagent.com/supporters'))).toBeNull();
  });
});
