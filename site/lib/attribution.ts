/** The campaign tags a visitor arrived with. */
export const UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"] as const;

export type Utm = Partial<Record<(typeof UTM_KEYS)[number], string>>;

const MAX_LENGTH = 100;

/** The campaign tags in an address's query, such as `window.location.search`. Empty ones are left out. */
export function utmFrom(search: string): Utm {
  const params = new URLSearchParams(search);
  const utm: Utm = {};
  for (const key of UTM_KEYS) {
    const value = params.get(key)?.trim().slice(0, MAX_LENGTH);
    if (value) utm[key] = value;
  }
  return utm;
}

/** What `rememberedUtm` reads back: only the known tags, only strings. */
export function parseUtm(stored: string | null): Utm | null {
  if (stored === null) return null;
  try {
    const value: unknown = JSON.parse(stored);
    if (typeof value !== "object" || value === null) return null;
    const utm: Utm = {};
    for (const key of UTM_KEYS) {
      const entry = (value as Record<string, unknown>)[key];
      if (typeof entry === "string" && entry !== "") utm[key] = entry.slice(0, MAX_LENGTH);
    }
    return utm;
  } catch {
    return null;
  }
}
