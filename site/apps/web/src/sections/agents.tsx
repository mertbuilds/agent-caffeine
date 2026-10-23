import { breakpoints, colors, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { useRef } from 'react';
import { AgentIcon } from '../components/agent-icons.tsx';
import { SectionHeading } from '../components/section-heading.tsx';
import { agentsMoreThan, markedAgents } from '../lib/agents.ts';
import { sceneProps } from '../lib/scene-props.ts';
import { useSeen } from '../lib/use-seen.ts';
import { m } from '../paraglide/messages.js';

type Agent = (typeof markedAgents)[number];

// Each row holds every agent so one copy is wider than any screen; the second starts half way round.
const HALF = Math.ceil(markedAgents.length / 2);
const ROWS = [
  { agents: markedAgents, back: false },
  { agents: [...markedAgents.slice(HALF), ...markedAgents.slice(0, HALF)], back: true },
];

const styles = create({
  chip: {
    alignItems: 'center',
    borderColor: colors.border,
    borderRadius: radius.lg,
    borderWidth: '1px',
    display: 'flex',
    flexShrink: 0,
    fontSize: text.sm,
    gap: spacing.s1_5,
    lineHeight: text.smLeading,
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s3,
    whiteSpace: 'nowrap',
  },
  icon: {
    flexShrink: 0,
    height: spacing.s4,
    width: spacing.s4,
  },
  list: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: spacing.s2,
    justifyContent: 'center',
    marginInline: 'auto',
    maxWidth: '1120px',
  },
  marquee: {
    marginInline: {
      [breakpoints.md]: `calc(-1 * ${spacing.s6})`,
      default: `calc(-1 * ${spacing.s4})`,
    },
  },
  section: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s10,
    scrollMarginTop: spacing.s20,
  },
  track: {
    display: 'flex',
    gap: spacing.s2,
    paddingRight: spacing.s2,
  },
});

function Chip({ agent }: { agent: Agent }) {
  return (
    <li {...props(styles.chip)}>
      <AgentIcon name={agent.icon} style={styles.icon} />
      {agent.name}
    </li>
  );
}

export function Agents() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0);

  return (
    <section id="agents" {...props(styles.section)}>
      <SectionHeading
        lead={m.agents_lead({ count: String(agentsMoreThan) })}
        title={m.agents_title()}
      />
      <div
        ref={ref}
        {...sceneProps(['agent-marquee', !seen && 'agent-marquee-paused'], styles.marquee)}
      >
        <ul {...sceneProps(['agent-list'], styles.list)}>
          {markedAgents.map((agent) => (
            <Chip agent={agent} key={agent.name} />
          ))}
        </ul>
        {ROWS.map((row) => (
          <div aria-hidden="true" className="agent-row" key={String(row.back)}>
            <div className={row.back ? 'agent-track agent-track-back' : 'agent-track'}>
              {(['first', 'second'] as const).map((copy) => (
                <ul key={copy} {...props(styles.track)}>
                  {row.agents.map((agent) => (
                    <Chip agent={agent} key={agent.name} />
                  ))}
                </ul>
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
