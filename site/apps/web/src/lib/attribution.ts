/** The campaign tags a visitor arrived with. Polar's checkout links take the same names. */
const UTM_KEYS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'] as const;

export type Utm = Partial<Record<(typeof UTM_KEYS)[number], string>>;

/** The source an order gets when the visitor arrived with no tags. */
const DEFAULT_SOURCE = 'caffeinagent.com';

const MAX_LENGTH = 100;

/** The campaign tags in an address's query, such as `window.location.search`. Empty ones are left out. */
export function utmFrom(search: string): Utm {
  const params = new URLSearchParams(search);
  const utm: Utm = {};
  for (const key of UTM_KEYS) {
    const value = params.get(key)?.trim().slice(0, MAX_LENGTH);
    if (value) {
      utm[key] = value;
    }
  }
  return utm;
}

/** What `rememberedUtm` reads back: only the known tags, only strings. */
export function parseUtm(stored: string | null): Utm | null {
  if (stored === null) {
    return null;
  }
  let value: unknown;
  try {
    value = JSON.parse(stored);
  } catch {
    return null;
  }
  if (typeof value !== 'object' || value === null) {
    return null;
  }
  const utm: Utm = {};
  for (const key of UTM_KEYS) {
    const entry: unknown = Reflect.get(value, key);
    if (typeof entry === 'string' && entry !== '') {
      utm[key] = entry.slice(0, MAX_LENGTH);
    }
  }
  return utm;
}

/**
 * A Polar checkout link that carries the visitor's source, so the order can be tied to it.
 * Polar stores these query parameters on the checkout's metadata. A link that cannot be read comes back as it is.
 */
export function checkoutUrlWith(checkoutUrl: string, utm: Utm): string {
  let url: URL;
  try {
    url = new URL(checkoutUrl);
  } catch {
    return checkoutUrl;
  }
  const tags: Utm = utm.utm_source ? utm : { utm_source: DEFAULT_SOURCE };
  for (const key of UTM_KEYS) {
    const value = tags[key];
    if (value) {
      url.searchParams.set(key, value);
    }
  }
  return url.toString();
}
