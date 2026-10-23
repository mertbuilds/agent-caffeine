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
