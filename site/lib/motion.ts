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
 * The hero laptop, in seconds into its loop: the prompt is typed and sent, the
 * lid starts to close one second later while the agent works on, and the lid
 * opens on the finished work.
 */
export const laptop = {
  loop: 8.45,
  rest: 2.5,
  type: [0.15, 0.95],
  sent: [1.05, 1.3],
  steps: [
    [1.4, 1.65],
    [1.9, 2.15],
    [2.5, 2.75],
  ],
  work: [1.05, 3.15],
  close: [2.05, 3.15],
  pillIn: [3.35, 3.75],
  race: [3.45, 6.05],
  pillOut: [5.9, 6.25],
  open: [6.35, 7.45],
} as const;

/**
 * The hero, in seconds into its loop: the app shows on the open display, the
 * lid closes, and the clock runs while the agents finish one by one. Two
 * minutes after the last one the Mac can sleep, and the menu dims. `clock`
 * pairs a time of the loop with the minutes that have passed by then: the
 * clock stands for a moment after each agent finishes. `lift`, `walk` and
 * `down` are for the cut where the closed laptop is carried, `notice` for the
 * cuts with the notification.
 */
export const heroScene = {
  loop: 10,
  rest: 0.8,
  close: [1.3, 2.3],
  clock: [
    [2.3, 0],
    [3.4, 12],
    [3.8, 12.9],
    [4.5, 21],
    [4.9, 21.9],
    [5.6, 30],
    [6, 30.9],
    [6.7, 39],
    [7.1, 39.9],
    [7.7, 41],
  ],
  dim: [8.9, 9.6],
  lift: [2.5, 3.2],
  walk: [2.8, 6.9],
  down: [6.9, 7.5],
  notice: [3.6, 4],
} as const;
