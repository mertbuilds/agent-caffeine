import { colors, fontWeight, leading, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link } from '@tanstack/react-router';
import { CompareSources, CompareTable } from '../components/compare-table.tsx';
import { m } from '../paraglide/messages.js';

const styles = create({
  body: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
    minWidth: 0,
  },
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
  more: {
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  section: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s10,
    marginInline: 'auto',
    maxWidth: '1120px',
    scrollMarginTop: spacing.s20,
    width: '100%',
  },
  title: {
    fontSize: '1.75rem',
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.2,
    textWrap: 'balance',
  },
});

/** The table on the home page, and the way to the page that says when to pick another tool. */
export function Compare() {
  return (
    <section id="compare" {...props(styles.section)}>
      <div {...props(styles.heading)}>
        <h2 {...props(styles.title)}>{m.compare_title()}</h2>
        <p {...props(styles.lead)}>{m.compare_lead()}</p>
      </div>
      <div {...props(styles.body)}>
        <CompareTable />
        <CompareSources />
        <p {...props(styles.more)}>
          <Link to="/compare">{m.compare_more()}</Link>
        </p>
      </div>
    </section>
  );
}
