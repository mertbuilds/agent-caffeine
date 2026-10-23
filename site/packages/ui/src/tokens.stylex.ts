import { defineConsts, defineVars } from '@stylexjs/stylex';

/**
 * The site's colours. Each one points at its variable in `src/tokens.css`,
 * which holds the value as light-dark(light, dark), so dark mode follows the
 * system, or the theme the visitor picked, with no media query here.
 */
export const colors = defineVars({
  accent: 'var(--accent)',
  appAmber: 'var(--app-amber)',
  appBlue: 'var(--app-blue)',
  bg: 'var(--bg)',
  border: 'var(--border)',
  brandDeep: 'var(--brand-deep)',
  brandLight: 'var(--brand-light)',
  fg: 'var(--fg)',
  hairline: 'var(--hairline)',
  muted: 'var(--muted)',
  panel: 'var(--panel)',
  panelFg: 'var(--panel-fg)',
  panelLine: 'var(--panel-line)',
  panelMuted: 'var(--panel-muted)',
  shadow: 'var(--shadow)',
  surface: 'var(--surface)',
});

/** Durations and easings, the `--duration-*` and `--ease-*` variables. */
export const motion = defineVars({
  durationFast: 'var(--duration-fast)',
  durationQuick: 'var(--duration-quick)',
  durationSlow: 'var(--duration-slow)',
  easeSmoothOut: 'var(--ease-smooth-out)',
});

/**
 * The font stacks (`--font-*`), then the system faces. Only Regular (400) and
 * Medium (500) of Suisse Intl are licensed, so no text goes above 500.
 */
export const fontFamily = defineConsts({
  mono: 'var(--font-mono), monospace',
  sans: 'var(--font-sans), system-ui, sans-serif',
});

export const fontWeight = defineConsts({
  medium: '500',
  normal: '400',
});

/** Font sizes, with the line height each one comes with. */
export const text = defineConsts({
  '2xl': '1.5rem',
  '2xlLeading': '2rem',
  base: '1rem',
  baseLeading: '1.5rem',
  lg: '1.125rem',
  lgLeading: '1.75rem',
  sm: '0.875rem',
  smLeading: '1.25rem',
  xl: '1.25rem',
  xlLeading: '1.75rem',
  xs: '0.75rem',
  xsLeading: '1rem',
});

export const leading = defineConsts({
  none: '1',
  normal: '1.5',
  relaxed: '1.625',
  snug: '1.375',
  tight: '1.25',
});

/** 0.25rem spacing scale; the key is the step (`s1_5` is 0.375rem). */
export const spacing = defineConsts({
  s0_5: '0.125rem',
  s1: '0.25rem',
  s1_5: '0.375rem',
  s10: '2.5rem',
  s12: '3rem',
  s14: '3.5rem',
  s16: '4rem',
  s2: '0.5rem',
  s2_5: '0.625rem',
  s20: '5rem',
  s24: '6rem',
  s28: '7rem',
  s3: '0.75rem',
  s3_5: '0.875rem',
  s32: '8rem',
  s4: '1rem',
  s5: '1.25rem',
  s6: '1.5rem',
  s7: '1.75rem',
  s8: '2rem',
  s9: '2.25rem',
});

export const radius = defineConsts({
  base: '0.25rem',
  full: '9999px',
  lg: '0.5rem',
  xl: '0.75rem',
  xl2: '1rem',
});

/** Min-width breakpoints, as `[breakpoints.md]: value` inside a property. */
export const breakpoints = defineConsts({
  lg: '@media (min-width: 1024px)',
  md: '@media (min-width: 768px)',
  sm: '@media (min-width: 640px)',
  xl: '@media (min-width: 1280px)',
});
