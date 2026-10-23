import { breakpoints, colors } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { easeInOut, useMotionValueEvent } from 'motion/react';
import { memo, useCallback, useLayoutEffect, useRef, useState } from 'react';
import { heroScene } from '../../lib/motion.ts';
import { stretch, useLoop } from '../../lib/playhead.ts';
import {
  detailOf,
  headlineText,
  ICON_AT_REST,
  iconLook,
  pose,
  RELEASE_AFTER,
  type Headline,
} from '../../lib/simulator.ts';
import { useLessMotion } from '../../lib/use-less-motion.ts';
import { useSeen } from '../../lib/use-seen.ts';
import { useTabHidden } from '../../lib/use-tab-hidden.ts';
import { m } from '../../paraglide/messages.js';
import { AgentIcon, type AgentIconName } from '../agent-icons.tsx';
import { Flow, PanelSurface } from '../agents-panel.tsx';
import { DESK, fixed, PHONE } from '../laptop/geometry.ts';
import { Laptop } from '../laptop/laptop.tsx';
import { MenuIcon } from '../menu-icon.tsx';
import { Robot } from '../robot.tsx';

/** Set inline: StyleX's CSS step rewrites light-dark(), which then draws nothing. */
const GREEN = 'light-dark(#28a745, #32d74b)';

/** The time on the menu bar when the lid closes, in minutes of the day. */
const CLOCK_START = 14 * 60 + 2;
/**
 * The glass of the open display in the scene, in hundredths of the scene's
 * width (`lidArt(0)` less the bezel and the chin). The open lid faces the eye,
 * so the glass is a plain rectangle, and the flat menu lies on it. Both views
 * have the open lid in the same place, so this is the glass of both.
 */
const GLASS = { height: 35, left: 23.07, round: 0.87, top: 6.21, width: 53.86 };
/** The gap between the glass's edge and the menu bar, in pixels at full size. */
const GAP = 3;

/** The widths of the page from which the scene has its next set width. StyleX bounds each one above by the next. */
const W375 = '@media (min-width: 375px)';
const W390 = '@media (min-width: 390px)';
const W430 = '@media (min-width: 430px)';
const SM = breakpoints.sm;
const LG = breakpoints.lg;
const XL = breakpoints.xl;

/** Seconds the check takes to come in. */
const CHECK_IN = 0.35;
/** How much of itself the desktop keeps in the outline of the display once the lid is closed. */
const DESKTOP_KEPT = 0.45;
/** Seconds the robot's tile takes to lose its colour, and the icon in the menu bar to go pale, once the Mac can sleep. */
const TONE_DOWN = 0.8;
/** How much of themselves the desktop and the outline keep once the Mac sleeps, and the menu, which has to stay readable. */
const ASLEEP = 0.45;
const MENU_ASLEEP = 0.75;
/** The moment of the loop that stands for all of it, for a reader who asked for less motion: the lid is closed, two agents work and one has just finished. */
const STILL = 3.38;

/** The agents at work, the longest first as the app lists them. `before` is the minutes each has worked when the lid closes, and `done` the minutes after that when it finishes. */
const AGENTS: ReadonlyArray<{
  before: number;
  done: number;
  folder: string;
  icon: AgentIconName;
  name: string;
}> = [
  { before: 11, done: 27, folder: 'wiki', icon: 'claudecode', name: 'Claude Code' },
  { before: 8, done: 18, folder: 'api', icon: 'codex', name: 'Codex' },
  { before: 5, done: 9, folder: 'website', icon: 'cursor', name: 'Cursor' },
];
const LAST_DONE = AGENTS[0]!;

const styles = create({
  agentLine: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    gap: '1px',
    lineHeight: '1rem',
    minWidth: 0,
  },
  agentName: {
    height: '1rem',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  agentRow: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.5rem',
    height: { [breakpoints.sm]: '2.5rem', default: '2rem' },
  },
  agents: {
    display: 'flex',
    flexDirection: 'column',
    paddingBlock: { [breakpoints.sm]: '0.25rem', default: '0.125rem' },
    paddingInline: { [breakpoints.sm]: '13px', default: '7px' },
  },
  apple: {
    flexShrink: 0,
    height: '0.95em',
    transform: 'translateY(-1px)',
    width: 'auto',
  },
  battery: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: '1px',
  },
  batteryCase: {
    borderColor: 'currentColor',
    borderRadius: '3.5px',
    borderStyle: 'solid',
    borderWidth: '1px',
    display: 'flex',
    height: '11px',
    opacity: 0.9,
    padding: '1px',
    width: '22px',
  },
  batteryCharge: {
    backgroundColor: 'currentColor',
    borderRadius: '1.5px',
    width: '72%',
  },
  batteryTip: {
    backgroundColor: 'currentColor',
    borderBottomRightRadius: '1px',
    borderTopRightRadius: '1px',
    height: '0.25rem',
    width: '1.5px',
  },
  check: {
    alignItems: 'center',
    borderRadius: '9999px',
    display: 'flex',
    flexShrink: 0,
    height: '1rem',
    justifyContent: 'center',
    width: '1rem',
  },
  checkMark: {
    color: 'white',
    height: '0.5rem',
    width: '0.5rem',
  },
  clock: {
    fontVariantNumeric: 'tabular-nums',
  },
  deskOnly: {
    display: { [breakpoints.sm]: 'block', default: 'none' },
  },
  desktop: {
    backgroundImage: 'radial-gradient(130% 100% at 50% 100%, #3b82f0, #12306e 65%, #0a1c44)',
    inset: 0,
    position: 'absolute',
  },
  detail: {
    alignItems: 'center',
    color: colors.panelMuted,
    display: 'flex',
    fontSize: '12px',
    height: '1rem',
    whiteSpace: 'nowrap',
  },
  divider: {
    backgroundColor: colors.panelLine,
    height: '1px',
  },
  fill: {
    inset: 0,
    position: 'absolute',
  },
  flex: {
    display: 'flex',
  },
  ground: {
    backgroundColor: colors.bg,
    inset: 0,
    position: 'absolute',
  },
  head: {
    alignItems: 'center',
    display: 'flex',
    gap: { [breakpoints.sm]: '0.75rem', default: '0.5rem' },
    height: { [breakpoints.sm]: 'auto', default: '3rem' },
    paddingBlock: { [breakpoints.sm]: '0.75rem', default: null },
    paddingInline: { [breakpoints.sm]: '1rem', default: '0.625rem' },
  },
  headline: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.125rem',
    minWidth: 0,
  },
  iconSlot: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.fg} 14%, transparent)`,
    borderRadius: '5px',
    display: 'flex',
    height: { [breakpoints.sm]: '22px', default: '18px' },
    paddingInline: { [breakpoints.sm]: '0.5rem', default: '0.375rem' },
  },
  idle: {
    opacity: 0.55,
  },
  layers: {
    position: 'absolute',
  },
  mark: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    height: { [breakpoints.sm]: '34px', default: '30px' },
    justifyContent: 'center',
    position: 'relative',
    width: { [breakpoints.sm]: '34px', default: '30px' },
  },
  markIcon: {
    height: { [breakpoints.sm]: '18px', default: '1rem' },
    width: { [breakpoints.sm]: '18px', default: '1rem' },
  },
  markTile: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 8%, transparent)`,
    borderRadius: { [breakpoints.sm]: '0.5rem', default: '7px' },
    display: 'flex',
    height: { [breakpoints.sm]: '1.75rem', default: '1.5rem' },
    justifyContent: 'center',
    width: { [breakpoints.sm]: '1.75rem', default: '1.5rem' },
  },
  menu: {
    '--full': { default: '520px', [SM]: '705px' },
    alignItems: 'center',
    display: 'flex',
    flexDirection: 'column',
    gap: '0.25rem',
    left: '50%',
    position: 'absolute',
    top: 0,
    transform: {
      default: 'translateX(-50%) scale(calc(485 / 520))',
      [LG]: 'translateX(-50%) scale(calc(630 / 705))',
      [SM]: 'translateX(-50%) scale(calc(810 / 705))',
      [W375]: 'translateX(-50%) scale(calc(578 / 520))',
      [W390]: 'translateX(-50%) scale(calc(603 / 520))',
      [W430]: 'translateX(-50%) scale(calc(670 / 520))',
      [XL]: 'translateX(-50%) scale(calc(810 / 705))',
    },
    transformOrigin: 'top',
  },
  menuBar: {
    alignItems: 'center',
    backdropFilter: 'blur(8px)',
    backgroundColor: `color-mix(in srgb, ${colors.surface} 88%, transparent)`,
    borderRadius: '4px',
    color: colors.fg,
    display: 'flex',
    fontSize: '13px',
    gap: '0.75rem',
    height: { [breakpoints.sm]: '1.5rem', default: '1.25rem' },
    paddingLeft: '0.625rem',
    paddingRight: '0.5rem',
    width: '100%',
  },
  menuIcon: {
    height: { [breakpoints.sm]: '1.25rem', default: '1rem' },
    width: { [breakpoints.sm]: '21px', default: '17px' },
  },
  muted: {
    color: colors.panelMuted,
  },
  outline: {
    height: '100%',
    inset: 0,
    overflow: 'visible',
    position: 'absolute',
    width: '100%',
  },
  panel: {
    boxShadow: `0 12px 32px ${colors.shadow}`,
    width: '100%',
  },
  panelBox: {
    width: { [breakpoints.sm]: '320px', default: '100%' },
  },
  phoneOnly: {
    display: { [breakpoints.sm]: 'none', default: null },
  },
  robot: {
    display: 'block',
    flexShrink: 0,
    height: { [breakpoints.sm]: '3rem', default: '2.25rem' },
    width: { [breakpoints.sm]: '3rem', default: '2.25rem' },
  },
  robotScale: {
    display: 'flex',
    transform: { [breakpoints.sm]: 'none', default: 'scale(0.75)' },
    transformOrigin: 'top left',
    width: '3rem',
  },
  root: {
    display: 'flex',
    justifyContent: 'center',
  },
  scene: {
    aspectRatio: { [breakpoints.sm]: '10 / 7', default: '100 / 59' },
    containerType: 'inline-size',
    position: 'relative',
    width: '100%',
  },
  sized: {
    flexShrink: 0,
    width: {
      default: '485px',
      [LG]: '630px',
      [SM]: '810px',
      [W375]: '578px',
      [W390]: '603px',
      [W430]: '670px',
      [XL]: '810px',
    },
  },
  spacer: {
    flex: 1,
  },
  subtitle: {
    color: colors.panelMuted,
    fontSize: '12px',
  },
  title: {
    fontSize: '15px',
    lineHeight: '1.25rem',
  },
  wifi: {
    flexShrink: 0,
    height: '0.75rem',
    width: '17px',
  },
});

/** The laptop as each size of the page sees it. On a phone the scene is wider than the page, as much as the laptop's widest part (59.34 hundredths of the scene) fits between the page's gutters, and less tall. */
const VIEWS = [
  { shown: styles.phoneOnly, view: PHONE },
  { shown: styles.deskOnly, view: DESK },
] as const;

/** The minutes that have passed since the lid closed, at `time` seconds into the loop. */
function minutesAt(time: number): number {
  const marks = heroScene.clock;
  for (let next = 1; next < marks.length; next += 1) {
    const [from, start] = marks[next - 1]!;
    const [to, end] = marks[next]!;
    if (time < to) {
      return start + (end - start) * Math.max(0, (time - from) / (to - from));
    }
  }
  return marks.at(-1)![1];
}

/** The second of the loop at which `minutes` have passed. */
function secondAt(minutes: number): number {
  return heroScene.clock.find((mark) => mark[1] >= minutes)?.[0] ?? heroScene.loop;
}

/**
 * What the app decides `minutes` after the lid closed, in the default mode
 * (`HoldPolicy.decide`): it keeps the Mac awake while an agent works and for
 * `RELEASE_AFTER` after the last one finished, and then the Mac can sleep.
 */
function headlineAt(minutes: number): Headline {
  const working = AGENTS.filter((agent) => minutes < agent.done);
  if (working.length > 0) {
    return {
      kind: 'working',
      subject: working.length === 1 ? { one: working[0]!.name } : { many: working.length },
    };
  }
  return (minutes - LAST_DONE.done) * 60 < RELEASE_AFTER
    ? { kind: 'finishedRecently', subject: { one: LAST_DONE.name } }
    : { kind: 'idle', subject: { many: AGENTS.length } };
}

/** The second of the loop at which the Mac can sleep. */
const ASLEEP_AT = secondAt(LAST_DONE.done + RELEASE_AFTER / 60);

function clock(minutes: number): string {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, '0')}`;
}

/**
 * What moves without a step is written by the playhead straight into the
 * style of the few elements it belongs to, each marked with `data-hero`: so a
 * frame of the loop changes a few numbers and draws no component again, and
 * no other element has its style worked out again. `closed` is how far the
 * lid has closed, `dimmed` how far the sleeping Mac has dimmed, `rest` how
 * far the robot and the icon have gone pale, and `checks` how far each
 * agent's check has come in.
 */
type Frame = { checks: ReadonlyArray<number>; closed: number; dimmed: number; rest: number };

const AT_START: Frame = { checks: AGENTS.map(() => 0), closed: 0, dimmed: 0, rest: 0 };

const STYLES: Record<string, (frame: Frame, place: number) => Record<string, string>> = {
  check: ({ checks }, place) => {
    const share = checks[place] ?? 0;
    return { opacity: String(share), transform: `scale(${cut4(0.6 + 0.4 * share)})` };
  },
  desktop: ({ closed, dimmed }) => ({
    opacity: String(cut4((1 - (1 - DESKTOP_KEPT) * closed) * (1 - (1 - ASLEEP) * dimmed))),
  }),
  icon: ({ rest }) => ({ opacity: String(cut4(1 - (1 - ICON_AT_REST) * rest)) }),
  menu: ({ dimmed }) => ({ opacity: String(cut4(1 - (1 - MENU_ASLEEP) * dimmed)) }),
  outline: ({ closed, dimmed }) => ({
    opacity: String(cut4(closed * (1 - (1 - ASLEEP) * dimmed))),
  }),
  // The robot takes its tone from this number (`rest` of `Robot`), and it reaches no other element.
  robot: ({ rest }) => ({ '--rest': String(rest) }),
};

/** The spans of the loop where something moves without a step: the lid, each check as it comes in, the robot going pale, and the dim. Between them the playhead only counts minutes. */
const MOVING = [
  heroScene.close,
  ...AGENTS.map(
    (agent) => [secondAt(agent.done), secondAt(agent.done) + CHECK_IN] as const,
  ).toReversed(),
  [ASLEEP_AT, ASLEEP_AT + TONE_DOWN] as const,
  heroScene.dim,
] as const;

type Target = { element: HTMLElement; last: Record<string, string>; name: string; place: number };

/** The marked elements under `root`, to write frames into. */
function targets(root: HTMLElement): Array<Target> {
  return Array.from(root.querySelectorAll<HTMLElement>('[data-hero]'), (element) => {
    const [name = '', place] = (element.dataset.hero ?? '').split('-');
    return { element, last: {}, name, place: Number(place ?? 0) };
  });
}

/** Writes a frame into the marked elements: only what differs from what was written there last. */
function paint(marked: ReadonlyArray<Target>, frame: Frame) {
  for (const target of marked) {
    for (const [property, value] of Object.entries(
      STYLES[target.name]?.(frame, target.place) ?? {},
    )) {
      if (target.last[property] !== value) {
        target.last[property] = value;
        target.element.style.setProperty(property, value);
      }
    }
  }
}

function cut4(value: number) {
  return Math.round(value * 1e4) / 1e4;
}

/** An agent's mark in the slot of its ring, as in the app's menu: the arc goes round while it works, and an idle agent's mark is pale and has no ring. The arc is the `ring-turn` of styles/scenes.css, which costs no frame. */
function Mark({ icon, working }: { icon: AgentIconName; working: boolean }) {
  return (
    <span {...props(styles.mark)}>
      <span {...props(styles.markTile, !working && styles.idle)}>
        <AgentIcon name={icon} style={styles.markIcon} />
      </span>
      {working && <span aria-hidden="true" className="ring-turn" />}
    </span>
  );
}

/** The check of the agent at `place` in the list, which comes in once it has finished. */
function Check({ place }: { place: number }) {
  return (
    <span
      aria-hidden="true"
      data-hero={`check-${place}`}
      {...props(styles.check)}
      style={{ background: GREEN }}
    >
      <svg
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.8"
        viewBox="0 0 10 8"
        {...props(styles.checkMark)}
      >
        <path d="M1 4.2 3.8 7 9 1" />
      </svg>
    </span>
  );
}

/**
 * The Mac's menu bar along the top of the display: the Apple mark, Wi-Fi, the battery, our icon with its menu open, and the clock,
 * `minute` minutes after the lid closed. Its corners are the display's, less the gap round it. With `still` a number that changes does not roll.
 */
const MenuBar = memo(function MenuBar({ minute, still }: { minute: number; still: boolean }) {
  const stance = pose(headlineAt(minute));
  return (
    <div {...props(styles.menuBar)}>
      <svg fill="currentColor" viewBox="0 0 814 1000" {...props(styles.apple)}>
        <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76.5 0-103.7 40.8-165.9 40.8s-105.6-57-155.5-127C46.7 790.7 0 663 0 541.8c0-194.4 126.4-297.5 250.8-297.5 66.1 0 121.2 43.4 162.7 43.4 39.5 0 101.1-46 176.3-46 28.5 0 130.9 2.6 198.3 99.2zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z" />
      </svg>
      <span {...props(styles.spacer)} />
      <svg
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.7"
        viewBox="0 0 17 12"
        {...props(styles.wifi)}
      >
        <path d="M1.2 4.4a10.4 10.4 0 0 1 14.6 0M3.9 7.1a6.6 6.6 0 0 1 9.2 0" />
        <circle cx="8.5" cy="10" fill="currentColor" r="1.1" stroke="none" />
      </svg>
      <span {...props(styles.battery)}>
        <span {...props(styles.batteryCase)}>
          <span {...props(styles.batteryCharge)} />
        </span>
        <span {...props(styles.batteryTip)} />
      </span>
      <span {...props(styles.iconSlot)}>
        {/* The playhead makes the icon pale, so the look itself keeps its full strength. */}
        <span data-hero="icon" {...props(styles.flex)}>
          <MenuIcon look={{ ...iconLook(stance), opacity: 1 }} style={styles.menuIcon} />
        </span>
      </span>
      <span {...props(styles.clock)}>
        <Flow still={still}>{clock(CLOCK_START + minute)}</Flow>
      </span>
    </div>
  );
});

/**
 * A cut of the app's menu that fits the display, `minute` minutes after the lid closed: the robot beside the headline, and the agents,
 * without the bar of controls at the bottom. An agent has its folder beside its name and its line below. With `still` a number that changes does not roll.
 */
const Panel = memo(function Panel({
  minute,
  paused,
  still,
}: {
  minute: number;
  paused: boolean;
  still: boolean;
}) {
  const line = headlineAt(minute);
  const stance = pose(line);
  const { subtitle, title } = headlineText(line);
  return (
    <PanelSurface
      label={m.hero_scene_menu_label()}
      scenes={[paused && 'panel-paused']}
      style={styles.panel}
    >
      {/* On a phone the head has a set height: its second line is taller with a number in it than without. */}
      <div {...props(styles.head)}>
        {/* A robot that sleeps stands still here: the one that breathes in its sleep is in the menu further down the page. On a phone it is three quarters of its size. */}
        <span data-hero="robot" {...props(styles.robot)}>
          <span {...props(styles.robotScale)}>
            <Robot
              paused={paused}
              pose={stance}
              rest={stance === 'asleep' ? 'var(--rest)' : undefined}
              size={48}
              still={stance === 'asleep'}
            />
          </span>
        </span>
        <p {...props(styles.headline)}>
          <span {...props(styles.title)}>{title}</span>
          <span {...props(styles.subtitle)}>
            <Flow still={still}>{subtitle}</Flow>
          </span>
        </p>
      </div>
      <div {...props(styles.divider)} />
      <ul {...props(styles.agents)}>
        {AGENTS.map((agent, place) => {
          const working = minute < agent.done;
          return (
            <li key={agent.icon} {...props(styles.agentRow)}>
              <Mark icon={agent.icon} working={working} />
              {/* A finished agent keeps the two lines of one at work, each of a set height, so its name stays where it was. In the app an idle agent has one line. */}
              <span {...props(styles.agentLine)}>
                <span {...props(styles.agentName, !working && styles.muted)}>
                  {m.hero_scene_agent({ folder: agent.folder, name: agent.name })}
                </span>
                {/* The number rolls in a taller box than the line, so the line shows what runs over it, and its words stand on the line of a line without a number. */}
                <span {...props(styles.detail)}>
                  {working ? (
                    <span>
                      <Flow still={still}>
                        {detailOf(
                          {
                            before: 'idle',
                            command: false,
                            since: -agent.before * 60,
                            state: 'working',
                          },
                          minute * 60,
                        )}
                      </Flow>
                    </span>
                  ) : (
                    // Staged, not the app's words: the app says "Finished a moment ago" for a minute and then "Idle for 9 minutes". Here a finished agent keeps one short word, so that what is done reads apart from what works.
                    m.hero_scene_finished()
                  )}
                </span>
              </span>
              {!working && <Check place={place} />}
            </li>
          );
        })}
      </ul>
    </PanelSurface>
  );
});

/** What of the loop changes in steps, and so is drawn again by React: the whole minutes since the lid closed, how far the lid has closed, and whether the story has just cut to another moment. */
type Beat = { closed: number; cutting: boolean; minute: number };

export function HeroScene() {
  const ref = useRef<HTMLDivElement>(null);
  const layers = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const play = seen && !hidden;
  const playhead = useLoop(play, heroScene.loop, heroScene.rest, MOVING);
  const reduced = useLessMotion();

  // Before the first play the scene stands at its start, which is also what the server draws.
  const [begun, setBegun] = useState(false);
  if (play && !begun) {
    setBegun(true);
  }

  const [beat, setBeat] = useState<Beat>({ closed: 0, cutting: true, minute: 0 });
  const last = useRef({ at: 1, winding: false });
  const frame = useRef<Frame>(AT_START);
  const marked = useRef<Array<Target>>([]);
  const drawn = useRef<Beat>({ closed: 0, cutting: true, minute: 0 });

  // One frame of the loop. The playhead winds back to the start before each
  // replay: the story cuts to its start at once, and over that time the lid
  // opens and the menu comes back from its sleep.
  const show = useCallback(
    (at: number) => {
      if (at !== last.current.at) {
        last.current = { at, winding: at < last.current.at };
      }
      const winding = last.current.winding;
      const wound = !reduced && winding ? at : null;
      const cutting = winding || !begun;
      const time = reduced ? STILL : cutting ? 0 : at * heroScene.loop;
      const closed = cut4(wound ?? stretch(time, ...heroScene.close, easeInOut));
      frame.current = {
        checks: AGENTS.map((agent) => {
          const finished = secondAt(agent.done);
          return cut4(stretch(time, finished, finished + CHECK_IN));
        }),
        closed,
        dimmed: cut4(wound ?? stretch(time, ...heroScene.dim, easeInOut)),
        rest: cut4(stretch(time, ASLEEP_AT, ASLEEP_AT + TONE_DOWN, easeInOut)),
      };
      paint(marked.current, frame.current);
      const minute = Math.floor(minutesAt(time));
      // React hears of a frame only when a step changed, which is a few dozen times in a loop.
      const now = drawn.current;
      if (now.minute !== minute || now.closed !== closed || now.cutting !== cutting) {
        drawn.current = { closed, cutting, minute };
        setBeat(drawn.current);
      }
    },
    [begun, reduced],
  );
  useMotionValueEvent(playhead, 'change', show);
  useLayoutEffect(() => show(playhead.get()), [playhead, show]);
  // What React has just drawn again, such as a check that came in, takes the frame it missed.
  useLayoutEffect(() => {
    if (layers.current !== null) {
      marked.current = targets(layers.current);
      paint(marked.current, frame.current);
    }
  }, [beat]);

  return (
    <div aria-label={m.hero_scene_label()} ref={ref} role="img" {...props(styles.root)}>
      {/* The scene has a set width at each size of the page, so the menu on its display has one known scale. */}
      <div aria-hidden="true" {...props(styles.sized)}>
        <div {...props(styles.scene)}>
          {VIEWS.map(({ shown, view }) => (
            <div
              key={view.id}
              {...props(styles.fill, shown)}
              style={{
                perspective: `${view.PERSPECTIVE}cqw`,
                perspectiveOrigin: `50% ${fixed(view.ORIGIN)}cqw`,
              }}
            >
              {/* The lid's own glass is dark: the one desktop of the scene lies flat over it, below. */}
              <Laptop closed={beat.closed} view={view} />
            </div>
          ))}
          <div
            ref={layers}
            {...props(styles.layers)}
            style={{
              height: `${GLASS.height}cqw`,
              left: `${GLASS.left}%`,
              top: `${GLASS.top}cqw`,
              width: `${GLASS.width}%`,
            }}
          >
            {/*
              One desktop that never moves: it lies on the glass of the open display and stays there, paler, as the lid
              goes down behind it. The page's ground under it keeps the moving lid from showing through, also while
              the menu is dim: so the ground itself never dims.
            */}
            <div {...props(styles.ground)} style={{ borderRadius: `${GLASS.round}cqw` }} />
            <div
              data-hero="desktop"
              {...props(styles.desktop)}
              style={{ borderRadius: `${GLASS.round}cqw` }}
            />
            <svg
              data-hero="outline"
              fill="none"
              viewBox={`0 0 ${GLASS.width} ${GLASS.height}`}
              {...props(styles.outline)}
              style={{ opacity: 0 }}
            >
              <rect
                height={GLASS.height}
                rx={GLASS.round}
                strokeDasharray="5 5"
                strokeWidth="1"
                style={{ stroke: 'var(--hairline)' }}
                vectorEffect="non-scaling-stroke"
                width={GLASS.width}
              />
            </svg>
            <div
              data-hero="menu"
              {...props(styles.menu)}
              style={{
                height: `calc(${GLASS.height / 100} * var(--full))`,
                padding: GAP,
                width: `calc(${GLASS.width / 100} * var(--full))`,
              }}
            >
              <MenuBar minute={beat.minute} still={beat.cutting} />
              <div {...props(styles.panelBox)}>
                <Panel minute={beat.minute} paused={!play} still={beat.cutting} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
