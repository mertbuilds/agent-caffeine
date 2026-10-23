import { describe, expect, it } from 'vitest';
import {
  CHECKOUT_URL,
  dollars,
  FULL_PRICE,
  LAUNCH_PRICE,
  LAUNCH_PRICE_ACTIVE,
  MACS,
  PORTAL_URL,
  PRICE,
  PRICE_NOW,
} from './pricing.ts';

describe('pricing', () => {
  it('puts the launch price below the full price', () => {
    expect(LAUNCH_PRICE).toBeLessThan(FULL_PRICE);
  });

  it('follows the launch switch for the price a buyer pays today', () => {
    expect(PRICE_NOW).toBe(LAUNCH_PRICE_ACTIVE ? LAUNCH_PRICE : FULL_PRICE);
    expect(PRICE).toBe(dollars(PRICE_NOW));
    expect(dollars(14)).toBe('$14');
  });

  it('activates one key on up to 3 Macs', () => {
    expect(MACS).toBe(3);
  });

  it('has the checkout and the purchases page on Polar', () => {
    expect(new URL(CHECKOUT_URL).hostname).toBe('buy.polar.sh');
    expect(new URL(PORTAL_URL).hostname).toBe('polar.sh');
  });
});
