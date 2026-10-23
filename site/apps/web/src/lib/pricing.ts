/**
 * Every price on the site comes from here. There is one plan: a key for up to 3 Macs, paid once,
 * with a year of updates.
 */

/** While true, the site shows the launch price next to the full price, which it strikes through. Set it to false to show the full price alone. */
export const LAUNCH_PRICE_ACTIVE = true;

/** US dollars, paid once. */
export const FULL_PRICE = 14;

/** US dollars, paid once, while `LAUNCH_PRICE_ACTIVE` is true. The checkout link carries the discount. */
export const LAUNCH_PRICE = 9;

/** How many Macs one key activates. */
export const MACS = 3;

/** The Polar checkout link. */
export const CHECKOUT_URL =
  'https://buy.polar.sh/polar_cl_uVXeh4hiiZ6r8meBrBlGm6ZIP7BXKMQrN7eoR0nsbht';

/** Where a buyer finds a lost key and moves it to another Mac. */
export const PORTAL_URL = 'https://polar.sh/mertbuilds/portal';

/** What a buyer pays today, in US dollars. */
export const PRICE_NOW = LAUNCH_PRICE_ACTIVE ? LAUNCH_PRICE : FULL_PRICE;

export function dollars(price: number): string {
  return `$${price}`;
}

/** "$9", for copy that names the price a buyer pays today. */
export const PRICE = dollars(PRICE_NOW);
