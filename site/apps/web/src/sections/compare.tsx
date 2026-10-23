import { spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link } from '@tanstack/react-router';
import { CompareSources, CompareTable } from '../components/compare-table.tsx';
import { SectionHeading, sectionStyles } from '../components/section-heading.tsx';
import { m } from '../paraglide/messages.js';

const styles = create({
  body: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
    minWidth: 0,
  },
  more: {
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
});

/** The table on the home page, and the way to the page that says when to pick another tool. */
export function Compare() {
  return (
    <section id="compare" {...props(sectionStyles.section)}>
      <SectionHeading lead={m.compare_lead()} title={m.compare_title()} />
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
