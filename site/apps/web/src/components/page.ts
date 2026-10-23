import {
  breakpoints,
  colors,
  fontWeight,
  leading,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create } from '@stylexjs/stylex';

/**
 * The frame of a page that reads like a document: compare, the blog, privacy
 * and terms. A column of 680px under the header, then the footer.
 */
export const page = create({
  column: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s10,
    marginInline: 'auto',
    maxWidth: '680px',
    minWidth: 0,
    width: '100%',
  },
  grow: {
    flex: 1,
  },
  header: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
  },
  lead: {
    color: colors.muted,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  main: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s12,
    isolation: 'isolate',
    minHeight: '100vh',
    overflowX: 'clip',
    paddingInline: { [breakpoints.md]: spacing.s6, default: spacing.s4 },
    paddingTop: '6.5rem',
    position: 'relative',
  },
  meta: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  title: {
    fontSize: { [breakpoints.md]: '2.5rem', default: '2rem' },
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.15,
    textWrap: 'balance',
  },
});
