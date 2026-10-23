import { spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { MenuBarSimulator } from '../components/menu-bar-simulator.tsx';
import { SectionHeading, sectionStyles } from '../components/section-heading.tsx';
import { m } from '../paraglide/messages.js';

const styles = create({
  oldName: {
    position: 'absolute',
    scrollMarginTop: spacing.s20,
    top: 0,
  },
  section: {
    alignItems: 'center',
    gap: spacing.s12,
    position: 'relative',
  },
});

export function Demo() {
  return (
    <section id="demo" {...props(sectionStyles.section, styles.section)}>
      {/* The name this section had, for a link that still has it. */}
      <span aria-hidden="true" id="how-it-works" {...props(styles.oldName)} />
      <SectionHeading lead={m.demo_lead()} title={m.demo_title()} />
      <MenuBarSimulator />
    </section>
  );
}
