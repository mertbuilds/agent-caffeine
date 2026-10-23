import {
  breakpoints,
  colors,
  fontWeight,
  leading,
  motion,
  radius,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import NumberFlow from '@number-flow/react';
import { create, props } from '@stylexjs/stylex';
import { useRef, type ReactNode } from 'react';
import {
  GroupRows,
  NotificationCut,
  PanelSurface,
  panelStyles,
} from '../components/agents-panel.tsx';
import { Robot } from '../components/robot.tsx';
import { SectionHeading, sectionStyles } from '../components/section-heading.tsx';
import { BATTERY_FLOOR, type Group } from '../lib/simulator.ts';
import { useLessMotion } from '../lib/use-less-motion.ts';
import { useSeen } from '../lib/use-seen.ts';
import { m } from '../paraglide/messages.js';

/** Still cuts of the app's menu, with the words of `PanelText.swift`. */
const WAITING: Group = {
  agent: 'claude',
  children: [],
  detail: 'Waiting for your answer for 4 minutes',
  icon: 'claudecode',
  layout: 'oneLine',
  open: null,
  place: 'below',
  state: 'waiting',
  title: 'Claude Code · wiki',
};

const ONE_OF_TEN: ReadonlyArray<Group> = [
  {
    agent: 'claude',
    children: [
      { detail: 'Working for 6 minutes', key: 'wiki-6e', label: 'wiki-6e' },
      { detail: null, key: 'idle', label: '9 idle sessions' },
    ],
    detail: '1 working',
    icon: 'claudecode',
    layout: 'oneLine',
    open: true,
    place: 'trailing',
    state: 'working',
    title: 'Claude Code',
  },
  {
    agent: 'codex',
    children: [],
    detail: 'Idle for 6 minutes',
    icon: 'codex',
    layout: 'oneLine',
    open: null,
    place: 'trailing',
    state: 'idle',
    title: 'Codex',
  },
];

/** The battery before it runs down, in percent, and how long the gauge takes, in milliseconds. */
const BATTERY_START = 34;
const DRAIN = 2400;
const DRAIN_TIMING = { duration: DRAIN, easing: 'linear' };
const RED = 'light-dark(#ff3b30, #ff453a)';

const styles = create({
  battery: {
    alignItems: 'center',
    display: 'flex',
    height: spacing.s7,
    position: 'relative',
    width: '58px',
  },
  batteryBody: {
    borderColor: colors.panelMuted,
    borderRadius: radius.lg,
    borderWidth: '1.5px',
    height: '100%',
    padding: spacing.s0_5,
    position: 'relative',
    width: '52px',
  },
  batteryCap: {
    backgroundColor: colors.panelMuted,
    borderBottomRightRadius: '0.125rem',
    borderTopRightRadius: '0.125rem',
    height: spacing.s2_5,
    marginLeft: spacing.s0_5,
    width: '3px',
  },
  batteryCharge: {
    display: 'block',
    height: '100%',
    transitionProperty: 'transform, background-color',
    transitionTimingFunction: 'linear',
  },
  batteryFloor: {
    backgroundColor: colors.panelMuted,
    bottom: spacing.s0_5,
    position: 'absolute',
    top: spacing.s0_5,
    width: '1px',
  },
  batteryRow: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s3,
  },
  batteryStop: {
    alignItems: 'center',
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
    height: '100%',
    justifyContent: 'center',
    paddingInline: spacing.s4,
  },
  batteryWell: {
    borderRadius: '4.5px',
    display: 'block',
    height: '100%',
    overflow: 'hidden',
  },
  cut: {
    backgroundColor: colors.surface,
    borderRadius: radius.xl,
    height: '11rem',
    overflow: 'hidden',
  },
  headline: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s0_5,
    minWidth: 0,
  },
  headlineRow: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s3,
    paddingBottom: spacing.s3,
    paddingInline: spacing.s4,
  },
  headlineTitle: {
    fontSize: '15px',
    lineHeight: '1.25rem',
  },
  level: {
    fontSize: text.lg,
    fontVariantNumeric: 'tabular-nums',
    lineHeight: text.lgLeading,
  },
  name: {
    fontWeight: fontWeight.medium,
  },
  notice: {
    maxWidth: '19rem',
    opacity: 0,
    transform: 'translateY(0.5rem)',
    transitionDuration: motion.durationSlow,
    transitionProperty: {
      '@media (prefers-reduced-motion: reduce)': 'none',
      default: 'opacity, transform',
    },
    transitionTimingFunction: motion.easeSmoothOut,
    width: '100%',
  },
  noticeShown: {
    opacity: 1,
    transform: 'translateY(0)',
  },
  pretty: {
    textWrap: 'pretty',
  },
  rows: {
    paddingInline: '13px',
    paddingTop: spacing.s2,
  },
  scene: {
    borderColor: colors.border,
    borderRadius: '20px',
    borderWidth: '1px',
    display: 'flex',
    flexDirection: 'column',
    padding: spacing.s2,
  },
  scenes: {
    display: 'grid',
    gap: spacing.s4,
    gridTemplateColumns: { [breakpoints.lg]: 'repeat(3, minmax(0, 1fr))', default: null },
    marginInline: 'auto',
    maxWidth: { [breakpoints.lg]: 'none', default: '36rem' },
    width: '100%',
  },
  sessions: {
    paddingInline: '13px',
  },
  still: {
    borderRadius: 0,
    borderWidth: 0,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    justifyContent: 'center',
  },
  text: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  title: {
    fontWeight: fontWeight.medium,
    lineHeight: leading.snug,
    textWrap: 'balance',
  },
  words: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s1_5,
    paddingBottom: spacing.s2,
    paddingInline: spacing.s2,
    paddingTop: spacing.s4,
  },
});

/** A battery that runs down to the level where the app lets the Mac sleep, and the notification the app then sends. */
function BatteryStop() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.6);
  const lessMotion = useLessMotion();
  const low = seen || lessMotion;
  const level = low ? BATTERY_FLOOR : BATTERY_START;
  const still = lessMotion ? '0ms' : undefined;
  return (
    <div ref={ref} {...props(styles.batteryStop)}>
      <div {...props(styles.batteryRow)}>
        <span aria-hidden="true" {...props(styles.battery)}>
          <span {...props(styles.batteryBody)}>
            {/* Inner radius = outer 8px - border 1.5px - padding 2px. The charge slides, so its corners keep their shape. */}
            <span {...props(styles.batteryWell)}>
              <span
                {...props(styles.batteryCharge)}
                style={{
                  background: low ? RED : 'var(--fg)',
                  transform: `translateX(${level - 100}%)`,
                  transitionDelay: still ?? `0ms, ${DRAIN - 300}ms`,
                  transitionDuration: still ?? `${DRAIN}ms, 300ms`,
                }}
              />
            </span>
            {/* The level where the app stops. */}
            <span
              {...props(styles.batteryFloor)}
              style={{ left: `calc(2px + ${BATTERY_FLOOR}% - ${(BATTERY_FLOOR / 100) * 4}px)` }}
            />
          </span>
          <span {...props(styles.batteryCap)} />
        </span>
        <span {...props(styles.level)}>
          <NumberFlow
            animated={!lessMotion}
            locales="en-US"
            opacityTiming={DRAIN_TIMING}
            spinTiming={DRAIN_TIMING}
            suffix="%"
            transformTiming={DRAIN_TIMING}
            trend={-1}
            value={level}
          />
        </span>
      </div>
      <div
        {...props(styles.notice, low && styles.noticeShown)}
        style={{ transitionDelay: low && !lessMotion ? `${DRAIN}ms` : '0ms' }}
      >
        <NotificationCut label={m.sleep_notification_label()}>
          <span {...props(styles.name)}>{m.app_name()}</span>
          <span {...props(styles.pretty)}>
            {m.sleep_notification_text({ floor: String(BATTERY_FLOOR) })}
          </span>
        </NotificationCut>
      </div>
    </div>
  );
}

function Scene({
  children,
  text: words,
  title,
}: {
  children: ReactNode;
  text: string;
  title: string;
}) {
  return (
    <li {...props(styles.scene)}>
      <div {...props(styles.cut)}>{children}</div>
      <div {...props(styles.words)}>
        <h3 {...props(styles.title)}>{title}</h3>
        <p {...props(styles.text)}>{words}</p>
      </div>
    </li>
  );
}

export function SleepScenes() {
  return (
    <section id="features" {...props(sectionStyles.section)}>
      <SectionHeading lead={m.sleep_lead()} title={m.sleep_title()} />
      <ul {...props(styles.scenes)}>
        <Scene text={m.sleep_waiting_text()} title={m.sleep_waiting_title()}>
          <PanelSurface
            label={m.sleep_waiting_label()}
            scenes={['panel-still']}
            style={styles.still}
          >
            <div {...props(styles.headlineRow)}>
              <Robot pose="attentive" size={56} still />
              <p {...props(styles.headline)}>
                <span {...props(styles.headlineTitle)}>{m.sleep_waiting_headline()}</span>
                <span {...props(styles.pretty, panelStyles.small, panelStyles.muted)}>
                  {m.sleep_waiting_reason()}
                </span>
              </p>
            </div>
            <div {...props(panelStyles.divider)} />
            <div {...props(styles.rows)}>
              <GroupRows group={WAITING} />
            </div>
          </PanelSurface>
        </Scene>
        <Scene
          text={m.sleep_lid_text({ floor: String(BATTERY_FLOOR) })}
          title={m.sleep_lid_title()}
        >
          <BatteryStop />
        </Scene>
        <Scene text={m.sleep_sessions_text()} title={m.sleep_sessions_title()}>
          <PanelSurface
            label={m.sleep_sessions_label()}
            scenes={['panel-still']}
            style={[styles.still, styles.sessions]}
          >
            {ONE_OF_TEN.map((group) => (
              <GroupRows group={group} key={group.agent} />
            ))}
          </PanelSurface>
        </Scene>
      </ul>
    </section>
  );
}
