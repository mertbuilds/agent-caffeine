import { colors, fontWeight, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create } from '@stylexjs/stylex';

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';

/**
 * The pill of the site's actions. Apply `pill.base` with one size and a look,
 * such as `pill.ink` for the main action on the page's ground. On the blue
 * pricing card, `pill.onBrand` takes the place of `pill.base`, with
 * `pill.brand` or `pill.brandOutline`.
 */
export const pill = create({
  base: {
    borderRadius: radius.full,
    display: 'inline-block',
    flexShrink: 0,
    fontWeight: fontWeight.medium,
    opacity: { ':hover': 0.8, default: null },
    textDecorationLine: 'none',
    transitionDuration: motion.durationQuick,
    transitionProperty: { default: 'opacity', [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  brand: {
    backgroundColor: 'white',
    boxShadow: {
      ':hover': '0 6px 16px -4px rgba(8, 30, 90, 0.45)',
      default: '0 1px 2px rgba(8, 30, 90, 0.25)',
    },
    color: colors.brandDeep,
  },
  brandOutline: {
    boxShadow: {
      ':hover': 'inset 0 0 0 1px #ffffff',
      default: 'inset 0 0 0 1px rgba(255, 255, 255, 0.55)',
    },
    color: 'white',
  },
  compact: {
    fontSize: '0.8rem',
    height: spacing.s7,
    lineHeight: spacing.s7,
    paddingInline: spacing.s3_5,
  },
  ink: {
    backgroundColor: colors.fg,
    color: colors.bg,
  },
  large: {
    fontSize: text.base,
    lineHeight: text.baseLeading,
    paddingBlock: spacing.s3,
    paddingInline: spacing.s6,
  },
  onBrand: {
    borderRadius: radius.full,
    display: 'inline-block',
    flexShrink: 0,
    fontWeight: fontWeight.medium,
    outlineColor: { ':focus-visible': 'white', default: null },
    textDecorationLine: 'none',
    transform: { ':hover': { default: 'translateY(-1px)', [LESS_MOTION]: 'none' }, default: null },
    transitionDuration: motion.durationQuick,
    transitionProperty: { default: 'transform, box-shadow', [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  small: {
    fontSize: text.sm,
    lineHeight: text.smLeading,
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s4,
  },
});
