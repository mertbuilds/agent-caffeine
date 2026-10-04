// Mirrors the --duration-* and --ease-* variables in app/globals.css.
export const duration = {
  quick: 0.15,
  fast: 0.25,
  slow: 0.4,
} as const;

export const easing = {
  smoothOut: [0.22, 1, 0.36, 1],
} as const;

/**
 * The drawings, in seconds, kept together so they can be slowed or quickened
 * at once. Each plays over its own length, stands finished for `rest`, winds
 * back over `back` and plays again.
 */
export const drawing = {
  hero: 7,
  without: 5,
  rest: 2,
  back: 0.4,
  stepSees: 3.2,
  stepHolds: 3.4,
  stepSleeps: 3,
  stepRest: 1.8,
} as const;
