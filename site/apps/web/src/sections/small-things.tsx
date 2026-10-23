import {
  breakpoints,
  colors,
  fontWeight,
  leading,
  radius,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import type { ReactNode } from 'react';
import {
  BatteryLine,
  Gear,
  NotificationCut,
  PanelSurface,
  Switch,
  TimerChoices,
  panelStyles,
} from '../components/agents-panel.tsx';
import { Robot } from '../components/robot.tsx';
import { SectionHeading, sectionStyles } from '../components/section-heading.tsx';
import { BATTERY_FLOOR, type Battery } from '../lib/simulator.ts';
import { m } from '../paraglide/messages.js';

/** Still cuts of the app, with the words of `PanelText.swift`, `AgentNotices.swift` and `PreferencesView.swift` (the Settings window). */

const NEAR_FLOOR: Battery = {
  charge: '27%',
  consequence: `sleeps at ${BATTERY_FLOOR}%`,
  floor: BATTERY_FLOOR,
  level: 'nearFloor',
  percent: 27,
  spoken: `Battery 27 percent, Agent Caffeine lets your Mac sleep at ${BATTERY_FLOOR} percent`,
};

/** The two shortcuts of Settings > Shortcuts (`ShortcutAction.title`) with their default keys. */
function shortcuts() {
  return [
    { keys: '⌃⌥⌘C', title: m.small_key_toggle() },
    { keys: '⌃⌥⌘P', title: m.small_key_pause() },
  ];
}

/** The lid from the side at three angles, with the share of your brightness `LidDimming.curve` gives at each. */
const LIDS = [
  { angle: 105, label: '105°', level: 1 },
  { angle: 24, label: '24°', level: 0.5 },
  { angle: 0, label: '0°', level: 0 },
];
const LID_STEP = 94;
const LID_HINGE = '2 68';
const LID_BODY = { fill: 'var(--bg)', stroke: 'var(--hairline)', strokeWidth: 1 };
const DISPLAY_OFF = 'color-mix(in srgb, var(--hairline) 15%, black)';
const LIGHT_STOPS = [
  [0, 0.5],
  [0.2, 0.36],
  [0.4, 0.22],
  [0.6, 0.11],
  [0.8, 0.03],
  [1, 0],
] as const;

// Up to the lg breakpoint only, so it never competes with an lg value: StyleX does not order overlapping min-width queries.
const SM_ONLY = '@media (min-width: 640px) and (max-width: 1023.98px)';

const styles = create({
  chip: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 10%, transparent)`,
    borderRadius: '0.375rem',
    boxShadow: `inset 0 0 0 0.5px ${colors.panelLine}`,
    display: 'flex',
    flexShrink: 0,
    height: '22px',
    paddingInline: spacing.s2,
  },
  chipKeys: {
    justifyContent: 'center',
    minWidth: '68px',
  },
  chipPicker: {
    gap: spacing.s1_5,
  },
  cut: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.xl,
    display: 'flex',
    height: '8rem',
    justifyContent: 'center',
    overflow: 'hidden',
    paddingInline: spacing.s4,
  },
  grow: {
    flex: '1 1 0%',
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
    paddingBlock: spacing.s2_5,
    paddingInline: spacing.s4,
  },
  headlineTitle: {
    fontSize: '15px',
    lineHeight: '1.25rem',
  },
  lid: {
    maxWidth: '22rem',
    width: '100%',
  },
  lidAngle: {
    fontVariantNumeric: 'tabular-nums',
  },
  meter: {
    display: 'flex',
    justifyContent: 'center',
    maxWidth: '19rem',
    paddingBlock: spacing.s3_5,
    paddingInline: spacing.s4,
    width: '100%',
  },
  name: {
    fontWeight: fontWeight.medium,
  },
  narrow: {
    gridColumn: { [breakpoints.lg]: 'span 2', default: null },
  },
  notification: {
    maxWidth: '19rem',
    width: '100%',
  },
  pauseMenu: {
    borderRadius: '10px',
    boxShadow: `0 8px 24px ${colors.shadow}`,
    padding: '5px',
  },
  pretty: {
    textWrap: 'pretty',
  },
  reachBar: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s2,
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s4,
  },
  reachCut: {
    maxWidth: '19rem',
    width: '100%',
  },
  row: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s2,
    height: spacing.s9,
  },
  rowApart: {
    gap: spacing.s3,
    justifyContent: 'space-between',
  },
  rowSwitch: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s3,
    justifyContent: 'space-between',
    paddingBlock: spacing.s2,
  },
  settings: {
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 4%, ${colors.panel})`,
    borderRadius: '10px',
    maxWidth: '19rem',
    paddingInline: spacing.s3,
    width: '100%',
  },
  shortcuts: {
    gridColumn: { [breakpoints.lg]: 'span 3', default: null, [SM_ONLY]: 'span 2' },
  },
  stop: {
    color: colors.accent,
  },
  text: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  thing: {
    borderColor: colors.border,
    borderRadius: '20px',
    borderWidth: '1px',
    display: 'flex',
    flexDirection: 'column',
    padding: spacing.s2,
  },
  things: {
    display: 'grid',
    gap: spacing.s4,
    gridTemplateColumns: {
      [breakpoints.lg]: 'repeat(6, minmax(0, 1fr))',
      default: null,
      [SM_ONLY]: 'repeat(2, minmax(0, 1fr))',
    },
    marginInline: 'auto',
    maxWidth: { [breakpoints.lg]: 'none', default: '36rem' },
    width: '100%',
  },
  title: {
    fontWeight: fontWeight.medium,
    lineHeight: leading.snug,
    textWrap: 'balance',
  },
  wide: {
    gridColumn: { [breakpoints.lg]: 'span 3', default: null },
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

/** A group of rows in Settings. */
function Rows({ children, label }: { children: ReactNode; label: string }) {
  return (
    <PanelSurface label={label} style={styles.settings}>
      {children}
    </PanelSurface>
  );
}

/** A still side view: the hero is the one place where the lid moves. */
function LidCut() {
  return (
    <svg aria-label={m.small_lid_label()} role="img" viewBox="0 0 300 98" {...props(styles.lid)}>
      <defs>
        {/* Brightest at the middle of the display, gone at both of its ends and at the end of the throw. */}
        <radialGradient
          cx="0"
          cy="0"
          gradientTransform="translate(31 68) scale(28 34)"
          gradientUnits="userSpaceOnUse"
          id="lid-cut-light"
          r="1"
        >
          {LIGHT_STOPS.map(([offset, opacity]) => (
            <stop
              key={offset}
              offset={offset}
              style={{ stopColor: 'var(--accent)', stopOpacity: opacity }}
            />
          ))}
        </radialGradient>
        <clipPath id="lid-cut-above">
          <rect height="112.5" width="300" x="-60" y="-40" />
        </clipPath>
      </defs>
      {LIDS.map((lid, index) => (
        <g key={lid.label} transform={`translate(${32 + index * LID_STEP} 0)`}>
          {/* The light starts under the lid and ends under the base: both are drawn over it. */}
          {lid.level > 0 ? (
            <g clipPath="url(#lid-cut-above)">
              <rect
                fill="url(#lid-cut-light)"
                height="34"
                opacity={lid.level}
                transform={`rotate(${-lid.angle} ${LID_HINGE})`}
                width="56"
                x="3"
                y="68"
              />
            </g>
          ) : null}
          <rect
            height="5"
            rx="2"
            style={LID_BODY}
            vectorEffect="non-scaling-stroke"
            width="62"
            x="0"
            y="70"
          />
          {/* The lid turns on the middle of its round end, so that end stays on the base at each angle. */}
          <g transform={`rotate(${-lid.angle} ${LID_HINGE})`}>
            <rect
              height="4"
              rx="2"
              style={LID_BODY}
              vectorEffect="non-scaling-stroke"
              width="62"
              x="0"
              y="66"
            />
            <rect
              height="1.5"
              rx="0.75"
              style={{ fill: DISPLAY_OFF }}
              width="59.5"
              x="1.25"
              y="67.25"
            />
            <rect
              height="1.5"
              opacity={lid.level}
              rx="0.75"
              style={{ fill: 'var(--accent)' }}
              width="59.5"
              x="1.25"
              y="67.25"
            />
          </g>
          <text
            fontSize="11"
            textAnchor="middle"
            x="31"
            y="94"
            {...props(styles.lidAngle)}
            style={{ fill: 'var(--muted)' }}
          >
            {lid.label}
          </text>
        </g>
      ))}
    </svg>
  );
}

function Thing({
  children,
  size,
  text: words,
  title,
}: {
  children: ReactNode;
  size: StyleXStyles;
  text: string;
  title: string;
}) {
  return (
    <li {...props(styles.thing, size)}>
      <div {...props(styles.cut)}>{children}</div>
      <div {...props(styles.words)}>
        <h3 {...props(styles.title)}>{title}</h3>
        <p {...props(styles.text)}>{words}</p>
      </div>
    </li>
  );
}

export function SmallThings() {
  return (
    <section id="small-things" {...props(sectionStyles.section)}>
      <SectionHeading lead={m.small_lead()} title={m.small_title()} />
      {/* Seven cards in rows of two, three and two: `wide` is half a row, `narrow` a third of one. */}
      <ul {...props(styles.things)}>
        <Thing size={styles.wide} text={m.small_lid_text()} title={m.small_lid_title()}>
          <LidCut />
        </Thing>
        <Thing size={styles.wide} text={m.small_sound_text()} title={m.small_sound_title()}>
          <Rows label={m.small_sound_label()}>
            <div {...props(styles.rowSwitch)}>
              <span {...props(styles.pretty)}>{m.small_sound_switch()}</span>
              <Switch on />
            </div>
            <div {...props(panelStyles.divider)} />
            <div {...props(styles.row)}>
              <span {...props(styles.grow)}>{m.small_sound()}</span>
              <span {...props(styles.chip, styles.chipPicker)}>
                {m.small_sound_tink()}
                <svg
                  aria-hidden="true"
                  fill="none"
                  height="10"
                  stroke="currentColor"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="1.5"
                  viewBox="0 0 8 10"
                  width="8"
                >
                  <path d="M1.5 3.5 4 1l2.5 2.5M1.5 6.5 4 9l2.5-2.5" />
                </svg>
              </span>
              <span {...props(styles.chip)}>{m.small_sound_play()}</span>
            </div>
          </Rows>
        </Thing>
        <Thing size={styles.narrow} text={m.small_reach_text()} title={m.small_reach_title()}>
          <PanelSurface
            label={m.small_reach_label()}
            scenes={['panel-still']}
            style={styles.reachCut}
          >
            <div {...props(styles.headlineRow)}>
              <Robot pose="reachable" size={40} still />
              <p {...props(styles.headline)}>
                <span {...props(styles.headlineTitle)}>{m.small_reach_headline()}</span>
                <span {...props(panelStyles.small, panelStyles.tabular, panelStyles.muted)}>
                  {m.small_reach_until()}
                </span>
              </p>
            </div>
            <div {...props(panelStyles.divider)} />
            <div aria-hidden="true" {...props(styles.reachBar)}>
              <span {...props(panelStyles.tabular, panelStyles.muted)}>
                {m.small_reach_until()}
              </span>
              <span {...props(styles.stop)}>{m.panel_stop()}</span>
              <span {...props(panelStyles.spacer)} />
              <Gear />
              <Switch on />
            </div>
          </PanelSurface>
        </Thing>
        <Thing size={styles.narrow} text={m.small_pause_text()} title={m.small_pause_title()}>
          <PanelSurface label={m.small_pause_label()} style={styles.pauseMenu}>
            <ul aria-hidden="true">
              <TimerChoices active={1} bar={{ reachable: false, reachableCost: null }} />
            </ul>
          </PanelSurface>
        </Thing>
        <Thing size={styles.narrow} text={m.small_notify_text()} title={m.small_notify_title()}>
          <NotificationCut label={m.small_notify_label()} style={styles.notification}>
            <span {...props(styles.name)}>{m.small_notify_waiting()}</span>
            <span {...props(styles.name)}>{m.small_notify_folder()}</span>
            <span>{m.small_notify_body()}</span>
          </NotificationCut>
        </Thing>
        <Thing size={styles.wide} text={m.small_battery_text()} title={m.small_battery_title()}>
          <PanelSurface label={m.small_battery_label()} style={styles.meter}>
            <BatteryLine battery={NEAR_FLOOR} />
          </PanelSurface>
        </Thing>
        <Thing size={styles.shortcuts} text={m.small_keys_text()} title={m.small_keys_title()}>
          <Rows label={m.small_keys_label()}>
            {shortcuts().map((shortcut, index) => (
              <div key={shortcut.keys}>
                {index > 0 && <div {...props(panelStyles.divider)} />}
                <div {...props(styles.row, styles.rowApart)}>
                  <span {...props(panelStyles.truncate)}>{shortcut.title}</span>
                  <span {...props(styles.chip, styles.chipKeys)}>{shortcut.keys}</span>
                </div>
              </div>
            ))}
          </Rows>
        </Thing>
      </ul>
    </section>
  );
}
