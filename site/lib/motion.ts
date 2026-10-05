// Mirrors the --duration-* and --ease-* variables in app/globals.css.
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
 * The hero laptop, in seconds into its loop: the prompt is typed and sent,
 * tool calls come in, the lid closes while the agent works on, and the lid
 * opens on the finished work.
 */
export const laptop = {
  loop: 11,
  rest: 2.5,
  welcome: [0, 0.3],
  type: [0.15, 0.95],
  sent: [1.05, 1.3],
  steps: [
    [1.5, 1.8],
    [1.9, 2.2],
    [2.6, 2.9],
    [3.0, 3.3],
    [3.7, 4.0],
    [4.0, 4.3],
  ],
  work: [1.05, 5.7],
  close: [4.6, 5.7],
  pillIn: [5.9, 6.3],
  race: [6.0, 8.6],
  pillOut: [8.45, 8.8],
  open: [8.9, 10.0],
} as const;
