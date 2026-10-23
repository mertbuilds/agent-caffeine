import { defineConsts } from '@stylexjs/stylex';

/**
 * Design tokens for the shadcn-cssinjs component set (src/ui).
 *
 * Each token wraps a CSS custom property defined in `src/theme.css`, which
 * points at the site's palette in `src/tokens.css` (light-dark() values, so
 * dark mode follows the system or the picked theme), so components reference
 * `colors.primary` / `radius.md` instead of stringly-typed `var(--primary)`.
 * `accent` and `muted` read the palette's surface directly, because the
 * palette's own `--accent` and `--muted` are a blue and an ink.
 *
 * App-level tokens (colours, spacing, type, breakpoints) live in
 * `src/tokens.stylex.ts`; this file is component-internal.
 */
export const colors = defineConsts({
  accent: 'var(--surface)',
  accentForeground: 'var(--accent-foreground)',
  background: 'var(--background)',
  border: 'var(--border)',
  card: 'var(--card)',
  cardForeground: 'var(--card-foreground)',
  destructive: 'var(--destructive)',
  foreground: 'var(--foreground)',
  input: 'var(--input)',
  muted: 'var(--surface)',
  mutedForeground: 'var(--muted-foreground)',
  popover: 'var(--popover)',
  popoverForeground: 'var(--popover-foreground)',
  primary: 'var(--primary)',
  primaryForeground: 'var(--primary-foreground)',
  ring: 'var(--ring)',
  secondary: 'var(--secondary)',
  secondaryForeground: 'var(--secondary-foreground)',
  sidebar: 'var(--sidebar)',
  sidebarAccent: 'var(--sidebar-accent)',
  sidebarAccentForeground: 'var(--sidebar-accent-foreground)',
  sidebarBorder: 'var(--sidebar-border)',
  sidebarForeground: 'var(--sidebar-foreground)',
  sidebarPrimary: 'var(--sidebar-primary)',
  sidebarPrimaryForeground: 'var(--sidebar-primary-foreground)',
  sidebarRing: 'var(--sidebar-ring)',
});

/**
 * Radius scale, pinned: surfaces (cards/dialogs/popovers) use 8px
 * (`--radius: 8px`); controls (buttons/inputs/select triggers) use `full`
 * (pill). sm through 2xl all resolve to the surface radius so registry
 * components render 8px corners regardless of which step they reference;
 * only pill shapes (`full`) diverge.
 */
export const radius = defineConsts({
  '2xl': 'var(--radius)',
  full: '9999px',
  lg: 'var(--radius)',
  md: 'var(--radius)',
  sm: 'var(--radius)',
  xl: 'var(--radius)',
});

/**
 * Control heights, one per size, shared by every form control (Button, Input,
 * Select trigger) so a field and the button next to it line up. `default` is
 * 36px, shadcn's h-9 for both inputs and buttons; `sm` is 28px for compact
 * triggers and icon buttons.
 */
export const controlHeight = defineConsts({
  default: '2.25rem',
  sm: '1.75rem',
});
