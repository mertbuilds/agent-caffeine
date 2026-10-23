import {
  breakpoints,
  colors,
  fontFamily,
  fontWeight,
  leading,
  radius,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import type { ReactNode } from 'react';
import { AgentIcon, type AgentIconName } from '../components/agent-icons.tsx';
import { AgentMark, PanelSurface, panelStyles } from '../components/agents-panel.tsx';
import { SectionHeading, sectionStyles } from '../components/section-heading.tsx';
import { m } from '../paraglide/messages.js';

/** Still cuts of an agent, of what it runs and of the app, with the words of `PanelText.swift` (the line of a hold) and of the command line tool. */

type Example = {
  agent: { icon: AgentIconName; name: string; prompt: string };
  ask: () => string;
  /** The line of the hold in the menu: the reason, and what `PanelText.hold` says below it. */
  row: { detail: () => string; title: () => string };
  /** A command the agent puts the tool in front of, or a call of the MCP tool `hold_awake`. */
  run: { command: string } | { input: string; tool: string };
};

const EXAMPLES: ReadonlyArray<Example> = [
  {
    agent: { icon: 'claudecode', name: 'Claude Code', prompt: '>' },
    ask: m.examples_render_ask,
    row: { detail: m.examples_render_detail, title: m.examples_render_title },
    run: { command: 'agent-caffeine hold --reason "Blender render" -- blender -b scene.blend -a' },
  },
  {
    agent: { icon: 'codex', name: 'Codex', prompt: '›' },
    ask: m.examples_train_ask,
    row: { detail: m.examples_train_detail, title: m.examples_train_title },
    run: { command: 'agent-caffeine hold --reason "Model training" -- python train.py' },
  },
  {
    agent: { icon: 'cursor', name: 'Cursor', prompt: '→' },
    ask: m.examples_tests_ask,
    row: { detail: m.examples_tests_detail, title: m.examples_tests_title },
    run: { command: 'agent-caffeine hold --reason "Test suite" -- npm test' },
  },
  {
    agent: { icon: 'opencode', name: 'opencode', prompt: '>' },
    ask: m.examples_migrate_ask,
    row: { detail: m.examples_migrate_detail, title: m.examples_migrate_title },
    run: { input: 'minutes: 90, reason: "Database migration"', tool: 'hold_awake' },
  },
];

/** The agents with a mark that "Set up for agents" writes the skill for (`SkillCatalog.swift`). */
const SKILL_AGENTS: ReadonlyArray<{ icon: AgentIconName; name: string }> = [
  { icon: 'claudecode', name: 'Claude Code' },
  { icon: 'codex', name: 'Codex' },
  { icon: 'opencode', name: 'opencode' },
  { icon: 'cursor', name: 'Cursor' },
  { icon: 'geminicli', name: 'Gemini CLI' },
  { icon: 'pi', name: 'Pi' },
  { icon: 'grok', name: 'Grok Build' },
  { icon: 'amp', name: 'Amp' },
  { icon: 'goose', name: 'goose' },
  { icon: 'openclaw', name: 'OpenClaw' },
];

const styles = create({
  askBox: {
    alignItems: 'flex-start',
    gap: spacing.s2,
  },
  askIcon: {
    flexShrink: 0,
    height: spacing.s4,
    marginTop: '1px',
    width: spacing.s4,
  },
  box: {
    backgroundColor: colors.bg,
    borderColor: colors.panelLine,
    borderRadius: '0.375rem',
    borderWidth: '1px',
    display: 'flex',
    flex: '1 1 0%',
    paddingBlock: spacing.s2,
    paddingInline: spacing.s2_5,
  },
  card: {
    borderColor: colors.border,
    borderRadius: '20px',
    borderWidth: '1px',
    display: 'grid',
    gridRow: 'span 3',
    gridTemplateRows: 'subgrid',
    padding: spacing.s2,
  },
  cards: {
    columnGap: spacing.s4,
    display: 'grid',
    gridTemplateColumns: { [breakpoints.lg]: 'repeat(2, minmax(0, 1fr))', default: null },
    marginInline: 'auto',
    maxWidth: { [breakpoints.lg]: 'none', default: '36rem' },
    rowGap: spacing.s4,
    width: '100%',
  },
  code: {
    fontFamily: fontFamily.mono,
    fontSize: '0.9em',
  },
  cut: {
    backgroundColor: colors.surface,
    borderRadius: radius.xl,
    display: 'grid',
    gridRow: 'span 3',
    gridTemplateRows: 'subgrid',
    minWidth: 0,
    padding: spacing.s1_5,
    paddingTop: spacing.s2,
    rowGap: spacing.s2_5,
  },
  fact: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s1_5,
  },
  facts: {
    columnGap: spacing.s8,
    display: 'grid',
    gridTemplateColumns: { [breakpoints.lg]: 'repeat(3, minmax(0, 1fr))', default: null },
    marginInline: 'auto',
    maxWidth: { [breakpoints.lg]: 'none', default: '36rem' },
    paddingInline: spacing.s2,
    rowGap: spacing.s6,
    width: '100%',
  },
  factText: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  factTitle: {
    fontWeight: fontWeight.medium,
    lineHeight: leading.snug,
    textWrap: 'balance',
  },
  hold: {
    alignItems: 'center',
    borderRadius: '0.375rem',
    display: 'flex',
    flex: '1 1 0%',
    gap: spacing.s2,
    paddingBlock: spacing.s1_5,
    paddingLeft: '7px',
    paddingRight: spacing.s3,
  },
  holdDetail: {
    textWrap: 'pretty',
  },
  holdText: {
    display: 'flex',
    flex: '1 1 0%',
    flexDirection: 'column',
    gap: '1px',
    lineHeight: '1rem',
    minWidth: 0,
  },
  line: {
    display: 'flex',
    fontFamily: fontFamily.mono,
    fontSize: '12px',
    gap: '1ch',
    lineHeight: '18px',
    minWidth: 0,
  },
  lineMark: {
    color: colors.muted,
    flexShrink: 0,
  },
  lineText: {
    minWidth: 0,
    overflowWrap: 'break-word',
  },
  muted: {
    color: colors.muted,
  },
  skill: {
    display: 'flex',
  },
  skillIcon: {
    height: spacing.s4,
    width: spacing.s4,
  },
  skills: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: spacing.s2,
    paddingTop: spacing.s1,
  },
  step: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s1,
    minWidth: 0,
  },
  stepLabel: {
    color: colors.muted,
    fontSize: '12px',
    lineHeight: '1rem',
    paddingInline: spacing.s1,
  },
  stop: {
    color: colors.accent,
    flexShrink: 0,
  },
});

/** A message with each part between backticks set as code. */
function WithCode({ text: message }: { text: string }) {
  return (
    <>
      {message.split('`').map((part, index) =>
        index % 2 === 1 ? (
          <code key={part} {...props(styles.code)}>
            {part}
          </code>
        ) : (
          part
        ),
      )}
    </>
  );
}

/** One part of an example: what it is, and the cut of it. */
function Step({ children, label }: { children: ReactNode; label: string }) {
  return (
    <div {...props(styles.step)}>
      <p {...props(styles.stepLabel)}>{label}</p>
      {children}
    </div>
  );
}

/** A line of a terminal. A line that wraps goes on under its text, not under its `mark`. */
function Line({ children, mark }: { children: ReactNode; mark?: string }) {
  return (
    <p {...props(styles.line)}>
      {mark === undefined ? null : (
        <span aria-hidden="true" {...props(styles.lineMark)}>
          {mark}
        </span>
      )}
      <span {...props(styles.lineText)}>{children}</span>
    </p>
  );
}

/**
 * Radius: the card 20px, less its 8px padding is the cut at 12px, less its 6px padding is each box inside at 6px.
 * The three parts lie on the rows of the list, so each part is as tall as the same part of the card next to it.
 */
function ExampleCard({ example }: { example: Example }) {
  const { agent, ask, row, run } = example;
  const title = row.title();
  return (
    <li {...props(styles.card)}>
      <div {...props(styles.cut)}>
        <Step label={m.examples_you_ask({ agent: agent.name })}>
          <div {...props(styles.box, styles.askBox)}>
            <AgentIcon name={agent.icon} style={styles.askIcon} />
            <Line mark={agent.prompt}>{ask()}</Line>
          </div>
        </Step>
        <Step
          label={
            'command' in run
              ? m.examples_runs({ agent: agent.name })
              : m.examples_calls({ agent: agent.name })
          }
        >
          <div {...props(styles.box)}>
            {'command' in run ? (
              <Line mark="$">{run.command}</Line>
            ) : (
              <Line>
                {`${run.tool} `}
                <span {...props(styles.muted)}>{run.input}</span>
              </Line>
            )}
          </div>
        </Step>
        <Step label={m.examples_menu_shows()}>
          <PanelSurface
            label={m.examples_row_label({ title })}
            scenes={['panel-still']}
            style={styles.hold}
          >
            <AgentMark icon={null} state="working" />
            <span {...props(styles.holdText)}>
              <span {...props(panelStyles.truncate)}>{title}</span>
              <span
                {...props(
                  styles.holdDetail,
                  panelStyles.small,
                  panelStyles.tabular,
                  panelStyles.muted,
                )}
              >
                {row.detail()}
              </span>
            </span>
            <span aria-hidden="true" {...props(styles.stop)}>
              {m.panel_stop()}
            </span>
          </PanelSurface>
        </Step>
      </div>
    </li>
  );
}

function Fact({ children, title }: { children: ReactNode; title: string }) {
  return (
    <li {...props(styles.fact)}>
      <h3 {...props(styles.factTitle)}>{title}</h3>
      {children}
    </li>
  );
}

export function Examples() {
  return (
    <section id="examples" {...props(sectionStyles.section)}>
      <SectionHeading lead={m.examples_lead()} title={m.examples_title()} />
      <ul {...props(styles.cards)}>
        {EXAMPLES.map((example) => (
          <ExampleCard example={example} key={example.agent.name} />
        ))}
      </ul>
      <ul {...props(styles.facts)}>
        <Fact title={m.examples_skill_title()}>
          <p {...props(styles.factText)}>{m.examples_skill_text()}</p>
          <ul {...props(styles.skills)}>
            {SKILL_AGENTS.map((agent) => (
              <li key={agent.name} {...props(styles.skill)}>
                <AgentIcon label={agent.name} name={agent.icon} style={styles.skillIcon} />
              </li>
            ))}
          </ul>
        </Fact>
        <Fact title={m.examples_command_title()}>
          <p {...props(styles.factText)}>
            <WithCode text={m.examples_command_text()} />
          </p>
        </Fact>
        <Fact title={m.examples_mcp_title()}>
          <p {...props(styles.factText)}>
            <WithCode text={m.examples_mcp_text()} />
          </p>
        </Fact>
      </ul>
    </section>
  );
}
