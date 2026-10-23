import { colors, fontWeight, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create } from '@stylexjs/stylex';

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';

/**
 * The pill of the site's actions. Apply `pill.base` with one size and a look,
 * such as `pill.ink` for the main action on the page's ground.
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
  small: {
    fontSize: text.sm,
    lineHeight: text.smLeading,
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s4,
  },
});
