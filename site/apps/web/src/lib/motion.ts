// Mirrors the --duration-* and --ease-* variables in @caffeinagent/ui/tokens.css.
export const duration = {
  // A word going or coming, a menu closing.
  quick: 0.15,
  // A menu opening.
  fast: 0.25,
  // The header opening back out of its pill.
  slow: 0.4,
  // The header gathering into its pill.
  verySlow: 0.5,
  // Each of the header's items after the one before it as they gather, and each item of its menu as it comes in.
  stagger: 0.04,
} as const;

export const easing = {
  smoothOut: [0.22, 1, 0.36, 1],
} as const;

/** A word coming into focus as the header gathers or opens out, in pixels. */
export const blur = {
  small: 2,
} as const;

/** How far a menu comes down from its button, and its items rise, in pixels. */
export const distance = {
  base: 8,
} as const;

export const scale = {
  // A menu opening.
  medium: 0.97,
  // A menu closing.
  tiny: 0.99,
} as const;

/** The looping drawings, in seconds. Every loop winds back over `back` before it plays again. */
export const drawing = {
  back: 0.4,
} as const;

/**
 * The hero, in seconds into its loop: the app shows on the open display, the
 * lid closes, and the clock runs while the agents finish one by one. Two
 * minutes after the last one the Mac can sleep, and the menu dims. `clock`
 * pairs a time of the loop with the minutes that have passed by then: the
 * clock stands for a moment after each agent finishes.
 */
export const heroScene = {
  clock: [
    [2.3, 0],
    [3, 9],
    [3.4, 9.9],
    [4, 18],
    [4.4, 18.9],
    [5, 27],
    [5.4, 27.9],
    [5.8, 29],
  ],
  close: [1.3, 2.3],
  dim: [7.3, 8],
  loop: 8.4,
  rest: 0.5,
} as const;
