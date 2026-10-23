import { colors, fontWeight, leading, spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';

/** A section of the home page: a column of the page's width, held below the header when a link jumps to it. */
export const sectionStyles = create({
  section: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s10,
    marginInline: 'auto',
    maxWidth: '1120px',
    scrollMarginTop: spacing.s20,
    width: '100%',
  },
});

const styles = create({
  heading: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
    marginInline: 'auto',
    maxWidth: '640px',
    textAlign: 'center',
  },
  lead: {
    color: colors.muted,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  title: {
    fontSize: '1.75rem',
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.2,
    textWrap: 'balance',
  },
});

export function SectionHeading({ lead, title }: { lead?: string; title: string }) {
  return (
    <div {...props(styles.heading)}>
      <h2 {...props(styles.title)}>{title}</h2>
      {lead === undefined ? null : <p {...props(styles.lead)}>{lead}</p>}
    </div>
  );
}
