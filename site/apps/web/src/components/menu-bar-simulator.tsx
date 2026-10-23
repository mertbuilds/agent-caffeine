import { breakpoints, colors, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import {
  useEffect,
  useEffectEvent,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactNode,
  type RefObject,
  type SyntheticEvent,
} from 'react';
import { easing } from '../lib/motion.ts';
import { sceneProps } from '../lib/scene-props.ts';
import {
  AGENTS,
  BATTERY_LEVELS,
  DEMO_MOVE,
  DEMO_PRESS,
  DEMO_START,
  INITIAL,
  PRESETS,
  advance,
  allowHelper,
  choiceOf,
  cueTarget,
  cueTime,
  demoStep,
  dismissHint,
  nextCue,
  preset,
  resume,
  setBattery,
  setChoice,
  setEnabled,
  setLid,
  setMode,
  setPower,
  startPause,
  startReachable,
  stopReachable,
  tickEvery,
  view,
  type Choice,
  type Cue,
  type PresetId,
  type SimState,
} from '../lib/simulator.ts';
import { track } from '../lib/track.ts';
import { useLessMotion } from '../lib/use-less-motion.ts';
import { useSeen } from '../lib/use-seen.ts';
import { useTabHidden } from '../lib/use-tab-hidden.ts';
import { m } from '../paraglide/messages.js';
import { AgentIcon } from './agent-icons.tsx';
import { AgentsPanel } from './agents-panel.tsx';
import { MenuIcon } from './menu-icon.tsx';

/** Stand-ins for the other status items, as wide as each glyph, in pixels. */
const GLYPHS = [16, 14, 20];

/** Two columns, where the controls and the panel are in sight together and the demo pointer can travel between them. */
const WIDE = '(min-width: 1024px)';
const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';
const COLOR_PROPERTIES =
  'color, background-color, border-color, text-decoration-color, fill, stroke';

const styles = create({
  agent: {
    alignItems: 'flex-start',
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s2,
    paddingBlock: spacing.s3,
  },
  agentAfter: {
    borderTopColor: colors.border,
    borderTopWidth: '1px',
  },
  agentIcon: {
    flexShrink: 0,
    height: spacing.s5,
    width: spacing.s5,
  },
  agentName: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s2,
    minWidth: 0,
  },
  agents: {
    borderBlockColor: colors.border,
    borderBlockWidth: '1px',
    display: 'flex',
    flexDirection: 'column',
  },
  caption: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: 1.5,
    maxWidth: '36rem',
    minHeight: { [breakpoints.sm]: '2lh', default: '3lh' },
    textAlign: { [breakpoints.lg]: 'center', default: null },
    textWrap: 'pretty',
  },
  chip: {
    borderColor: { ':hover': colors.fg, default: colors.border },
    borderRadius: radius.full,
    borderWidth: '1px',
    color: colors.fg,
    flexShrink: 0,
    fontSize: text.sm,
    lineHeight: 1.25,
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s3,
    transitionDuration: motion.durationFast,
    transitionProperty: { default: COLOR_PROPERTIES, [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
    whiteSpace: 'nowrap',
  },
  chipOn: {
    backgroundColor: colors.fg,
    borderColor: colors.fg,
    color: colors.bg,
  },
  chips: {
    '::-webkit-scrollbar': {
      display: 'none',
    },
    display: 'flex',
    flexWrap: { [breakpoints.sm]: 'wrap', default: null },
    gap: spacing.s2,
    justifyContent: { [breakpoints.lg]: 'center', default: null },
    marginInline: { [breakpoints.sm]: 0, default: `calc(-1 * ${spacing.s4})` },
    overflowX: { [breakpoints.sm]: 'visible', default: 'auto' },
    paddingBlock: spacing.s0_5,
    paddingInline: { [breakpoints.sm]: 0, default: spacing.s4 },
    scrollbarWidth: 'none',
  },
  clock: {
    fontVariantNumeric: 'tabular-nums',
    textAlign: 'center',
    width: spacing.s14,
  },
  column: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s3,
  },
  controls: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s6,
    minWidth: 0,
  },
  dimmed: {
    opacity: 0.4,
  },
  dot: {
    backgroundColor: colors.accent,
    borderRadius: radius.full,
    height: spacing.s1_5,
    position: 'relative',
    width: spacing.s1_5,
  },
  fades: {
    transitionDuration: motion.durationFast,
    transitionProperty: { default: 'opacity', [LESS_MOTION]: 'none' },
    transitionTimingFunction: 'cubic-bezier(0.4, 0, 0.2, 1)',
  },
  fill: {
    backgroundColor: `color-mix(in srgb, ${colors.accent} 16%, transparent)`,
    inset: 0,
    position: 'absolute',
    transformOrigin: 'left',
  },
  glyph: {
    alignItems: 'center',
    display: 'flex',
    height: '22px',
    paddingInline: spacing.s2,
  },
  glyphBar: {
    backgroundColor: 'currentColor',
    borderRadius: '3px',
    height: spacing.s3_5,
    opacity: 0.3,
  },
  grid: {
    display: 'grid',
    gap: { [breakpoints.lg]: spacing.s16, default: spacing.s8 },
    gridTemplateColumns: { [breakpoints.lg]: 'minmax(0, 24rem) minmax(0, 36rem)', default: null },
    justifyContent: { [breakpoints.lg]: 'center', default: null },
  },
  head: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s4,
    justifyContent: 'space-between',
    minHeight: spacing.s6,
  },
  icon: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.fg} 14%, transparent)`,
    borderRadius: '5px',
    display: 'flex',
    height: '22px',
    paddingInline: spacing.s2,
    position: 'relative',
  },
  iconGlyph: {
    height: spacing.s5,
    position: 'relative',
    width: '21px',
  },
  label: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  machine: {
    alignItems: 'flex-end',
    alignSelf: 'flex-start',
    borderColor: colors.border,
    borderRadius: '10px',
    borderWidth: '1px',
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s1,
    minWidth: 0,
    order: { [breakpoints.lg]: 0, default: -9999 },
    padding: spacing.s1,
    paddingBottom: spacing.s6,
    width: '100%',
  },
  menuBar: {
    alignItems: 'center',
    backdropFilter: 'blur(8px)',
    backgroundColor: `color-mix(in srgb, ${colors.surface} 85%, transparent)`,
    borderRadius: '0.375rem',
    color: colors.fg,
    display: 'flex',
    fontSize: '13px',
    height: spacing.s6,
    justifyContent: 'flex-end',
    paddingInline: spacing.s1_5,
    width: '100%',
  },
  note: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: 1.5,
    textWrap: 'pretty',
  },
  panel: {
    marginRight: { [breakpoints.sm]: '3.875rem', default: null },
    minHeight: '20.5rem',
    width: { [breakpoints.sm]: '320px', default: '100%' },
  },
  playButton: {
    alignItems: 'center',
    borderColor: { ':hover': colors.fg, default: colors.border },
    borderRadius: radius.full,
    borderWidth: '1px',
    color: colors.fg,
    display: 'flex',
    height: spacing.s6,
    justifyContent: 'center',
    transitionDuration: motion.durationFast,
    transitionProperty: { default: COLOR_PROPERTIES, [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
    width: spacing.s6,
  },
  playGlyph: {
    height: spacing.s2_5,
    width: spacing.s2_5,
  },
  playing: {
    alignItems: 'center',
    display: 'flex',
    fontSize: text.sm,
    gap: spacing.s2,
    lineHeight: text.smLeading,
  },
  pointer: {
    left: 0,
    pointerEvents: 'none',
    position: 'absolute',
    top: 0,
    zIndex: 20,
  },
  pointerArrow: {
    display: 'block',
    filter: `drop-shadow(0 1px 1px ${colors.shadow})`,
    height: '23px',
    transform: 'scale(1)',
    transformOrigin: '2px 2px',
    transitionDuration: motion.durationQuick,
    transitionProperty: 'transform',
    transitionTimingFunction: motion.easeSmoothOut,
    width: '17px',
  },
  pressing: {
    transform: 'scale(0.85)',
  },
  pulse: {
    backgroundColor: colors.accent,
    borderRadius: '5px',
    inset: 0,
    opacity: 0,
    position: 'absolute',
  },
  relative: {
    position: 'relative',
  },
  ring: {
    backgroundColor: `color-mix(in srgb, ${colors.accent} 20%, transparent)`,
    borderColor: colors.accent,
    borderRadius: radius.full,
    borderWidth: '2px',
    height: spacing.s10,
    left: `calc(-1 * ${spacing.s5})`,
    opacity: 0,
    position: 'absolute',
    top: `calc(-1 * ${spacing.s5})`,
    width: spacing.s10,
  },
  root: {
    display: 'flex',
    flexDirection: 'column',
    gap: { [breakpoints.lg]: spacing.s10, default: spacing.s8 },
    maxWidth: { [breakpoints.lg]: 'none', default: '36rem' },
    position: 'relative',
    width: '100%',
  },
  segment: {
    borderRadius: radius.full,
    color: { ':hover': colors.fg, default: colors.muted },
    fontSize: text.sm,
    height: spacing.s7,
    lineHeight: text.smLeading,
    paddingInline: spacing.s2_5,
    transitionDuration: motion.durationFast,
    transitionProperty: { default: COLOR_PROPERTIES, [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
    whiteSpace: 'nowrap',
  },
  segmented: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    display: 'flex',
    flexShrink: 0,
    padding: spacing.s0_5,
  },
  segmentOn: {
    backgroundColor: colors.bg,
    boxShadow: `0 1px 2px ${colors.shadow}`,
    color: colors.fg,
  },
  setting: {
    alignItems: 'center',
    columnGap: spacing.s3,
    display: 'flex',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    rowGap: spacing.s2,
  },
  srOnly: {
    borderWidth: 0,
    clip: 'rect(0, 0, 0, 0)',
    height: '1px',
    margin: '-1px',
    overflow: 'hidden',
    padding: 0,
    position: 'absolute',
    whiteSpace: 'nowrap',
    width: '1px',
  },
  stopped: {
    color: colors.muted,
  },
  tabular: {
    fontVariantNumeric: 'tabular-nums',
  },
  tag: {
    alignItems: 'center',
    borderColor: colors.border,
    borderRadius: radius.full,
    borderWidth: '1px',
    color: colors.fg,
    display: 'flex',
    gap: spacing.s1_5,
    height: spacing.s6,
    overflow: 'hidden',
    paddingLeft: spacing.s2,
    paddingRight: spacing.s2_5,
    position: 'relative',
  },
  top: {
    alignItems: { [breakpoints.lg]: 'center', default: null },
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s3,
  },
  truncate: {
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
});

function isNode(target: EventTarget): target is Node {
  return 'nodeType' in target;
}

function isElement(target: EventTarget): target is Element {
  return isNode(target) && target.nodeType === Node.ELEMENT_NODE;
}

function subscribeWide(onChange: () => void): () => void {
  const query = window.matchMedia(WIDE);
  query.addEventListener('change', onChange);
  return () => query.removeEventListener('change', onChange);
}

function useWide(): boolean {
  return useSyncExternalStore(
    subscribeWide,
    () => window.matchMedia(WIDE).matches,
    () => false,
  );
}

/** How many times `value` has changed since the first draw, to replay a one-off animation on each change. */
function useChanges(value: string): number {
  const [last, setLast] = useState(value);
  const [count, setCount] = useState(0);
  if (last !== value) {
    setLast(value);
    setCount(count + 1);
  }
  return count;
}

type Point = { x: number; y: number };

/**
 * Where the demo presses a control, from the simulator's corner: near its
 * lower right, so the pointer leaves the label in sight, or its middle when
 * there is no pointer.
 */
function pointAt(root: HTMLElement, name: string, middle = false): Point | null {
  const element = root.querySelector(`[data-demo="${name}"]`);
  if (element === null) {
    return null;
  }
  const box = element.getBoundingClientRect();
  const origin = root.getBoundingClientRect();
  if (middle) {
    return {
      x: box.left - origin.left + box.width / 2,
      y: box.top - origin.top + box.height / 2,
    };
  }
  return {
    x: box.right - origin.left - Math.min(10, box.width / 3),
    y: box.bottom - origin.top - 4,
  };
}

type Fill = { key: string; ms: number } | 'full' | null;

/** The demo's status: a tag with a live dot that fills up to the next step, and the stop and play button. */
function Playing({
  fill,
  live,
  on,
  onToggle,
  ref,
}: {
  fill: Fill;
  live: boolean;
  on: boolean;
  onToggle: () => void;
  ref: RefObject<HTMLDivElement | null>;
}) {
  return (
    <div ref={ref} {...props(styles.playing)}>
      {on ? (
        <span data-demo="tag" {...props(styles.tag)}>
          {fill !== null && (
            <span
              aria-hidden="true"
              key={fill === 'full' ? 'full' : fill.key}
              {...sceneProps([fill !== 'full' && 'demo-fill'], styles.fill)}
              style={fill === 'full' ? undefined : { animationDuration: `${fill.ms}ms` }}
            />
          )}
          <span aria-hidden="true" {...sceneProps([live && 'demo-live'], styles.dot)} />
          <span {...props(styles.relative)}>{m.demo_playing()}</span>
        </span>
      ) : (
        <span {...props(styles.stopped)}>{m.demo_stopped()}</span>
      )}
      <button
        aria-label={on ? m.demo_stop() : m.demo_play()}
        onClick={onToggle}
        type="button"
        {...props(styles.playButton)}
      >
        <svg
          aria-hidden="true"
          fill="currentColor"
          viewBox="0 0 10 10"
          {...props(styles.playGlyph)}
        >
          {on ? (
            <rect height="7" rx="1" width="7" x="1.5" y="1.5" />
          ) : (
            <path d="M2.5 1.2v7.6a.5.5 0 0 0 .76.43l6.1-3.8a.5.5 0 0 0 0-.86l-6.1-3.8a.5.5 0 0 0-.76.43z" />
          )}
        </svg>
      </button>
    </div>
  );
}

/** The demo's arrow, its tip on `at`; it dips while it presses. */
function Pointer({ at, pressing }: { at: Point; pressing: boolean }) {
  return (
    <span
      aria-hidden="true"
      {...sceneProps(['demo-in'], styles.pointer)}
      style={{
        transform: `translate(${at.x - 2}px, ${at.y - 2}px)`,
        transition: `transform ${DEMO_MOVE}ms var(--ease-smooth-out)`,
      }}
    >
      <svg viewBox="0 0 14 19" {...props(styles.pointerArrow, pressing && styles.pressing)}>
        <path
          d="M1.5 1.5v14.2l3.5-3.4 2.4 5.4 2.4-1.1-2.4-5.3h4.9z"
          fill="var(--fg)"
          stroke="var(--bg)"
          strokeLinejoin="round"
          strokeWidth="1.2"
        />
      </svg>
    </span>
  );
}

function Segmented({ children, label }: { children: ReactNode; label: string }) {
  return (
    <div aria-label={label} role="group" {...props(styles.segmented)}>
      {children}
    </div>
  );
}

function Setting({ children, label }: { children: ReactNode; label: string }) {
  return (
    <div {...props(styles.setting)}>
      <span {...props(styles.label)}>{label}</span>
      <Segmented label={label}>{children}</Segmented>
    </div>
  );
}

function choices(): ReadonlyArray<{ choice: Choice; spoken: string; title: string }> {
  return [
    { choice: 'working', spoken: m.demo_choice_working_spoken(), title: m.demo_choice_working() },
    { choice: 'waiting', spoken: m.demo_choice_waiting_spoken(), title: m.demo_choice_waiting() },
    { choice: 'idle', spoken: m.demo_choice_idle_spoken(), title: m.demo_choice_idle() },
    // Not "Closed": that is the word of the lid.
    { choice: 'closed', spoken: m.demo_choice_quit_spoken(), title: m.demo_choice_quit() },
  ];
}

export function MenuBarSimulator() {
  const ref = useRef<HTMLDivElement>(null);
  const pauseRef = useRef<HTMLDivElement>(null);
  const used = useRef(false);
  const seen = useSeen(ref, 0.2);
  const hidden = useTabHidden();
  const lessMotion = useLessMotion();
  const wide = useWide();
  const [sim, setSim] = useState<SimState>(INITIAL);
  const [chosen, setChosen] = useState<PresetId | null>(demoStep(0).preset);
  const [autoplay, setAutoplay] = useState(true);
  const [cue, setCue] = useState<Cue>(DEMO_START);
  const [point, setPoint] = useState<Point | null>(null);
  const [ring, setRing] = useState<{ at: Point; id: number } | null>(null);
  const demoing = autoplay && !lessMotion;
  const playing = demoing && seen && !hidden;
  const marked = demoing ? demoStep(cue.step).preset : chosen;
  const caption = PRESETS.find((entry) => entry.id === marked)?.point ?? null;
  const shown = view(sim);
  const every = tickEvery(sim);
  const target = cueTarget(cue) ?? 'tag';
  const waiting = cue.phase === 'lead' || cue.phase === 'hold';
  const fill: Fill = !waiting
    ? 'full'
    : playing
      ? { key: `${cue.step}-${cue.phase}`, ms: cueTime(cue) }
      : null;
  const flips = useChanges(String(shown.held));
  const onBattery = sim.power === 'battery';

  const press = useEffectEvent((name: string) => {
    const root = ref.current;
    const element = root?.querySelector<HTMLElement>(`[data-demo="${name}"]`);
    if (root === null || element === null || element === undefined) {
      return;
    }
    // On a narrow screen the situations are one row that scrolls: the one being pressed comes into it.
    const row = element.closest<HTMLElement>('[data-scroller]');
    if (row !== null && row.scrollWidth > row.clientWidth) {
      row.scrollTo({
        behavior: 'smooth',
        left: element.offsetLeft - (row.clientWidth - element.offsetWidth) / 2,
      });
    }
    element.animate(
      [{ transform: 'scale(1)' }, { transform: 'scale(0.94)' }, { transform: 'scale(1)' }],
      {
        duration: 2 * DEMO_PRESS,
        easing: `cubic-bezier(${easing.smoothOut.join(',')})`,
      },
    );
    const at = pointAt(root, name, !wide);
    if (at !== null && wide) {
      setRing((last) => ({ at, id: (last?.id ?? 0) + 1 }));
    }
  });

  useEffect(() => {
    if (!playing) {
      return;
    }
    const timer = window.setTimeout(() => {
      const after = nextCue(cue);
      if (cue.phase === 'move') {
        press(target);
      }
      if (after.phase === 'hold') {
        setSim((state) => preset(state, demoStep(after.step).preset));
      }
      setCue(after);
    }, cueTime(cue));
    return () => window.clearTimeout(timer);
  }, [playing, cue, target]);

  useEffect(() => {
    const root = ref.current;
    if (!demoing || root === null) {
      return;
    }
    const place = () => setPoint((last) => pointAt(root, target) ?? last);
    place();
    window.addEventListener('resize', place);
    return () => window.removeEventListener('resize', place);
  }, [demoing, target]);

  useEffect(() => {
    if (every === null || !seen || hidden) {
      return;
    }
    const timer = window.setInterval(() => setSim((state) => advance(state, every)), every);
    return () => window.clearInterval(timer);
  }, [every, seen, hidden]);

  function fromPause(event: SyntheticEvent) {
    const node = event.target;
    return isNode(node) && pauseRef.current?.contains(node) === true;
  }

  /** Counts the first control a visitor presses. The demo presses nothing itself: it only draws a pointer. */
  function countUse(event: SyntheticEvent) {
    const element = event.target;
    if (used.current || !isElement(element)) {
      return;
    }
    const control = fromPause(event)
      ? 'demo'
      : (element.closest('[data-demo]')?.getAttribute('data-demo') ??
        (element.closest("button, [role='menuitem'], [role='option'], [role='switch']") === null
          ? null
          : 'panel'));
    if (control !== null) {
      used.current = true;
      track('simulator_use', { control });
    }
  }

  function stopDemo() {
    if (demoing) {
      setAutoplay(false);
      setChosen(demoStep(cue.step).preset);
      setPoint(null);
      setRing(null);
    }
  }

  function change(next: (state: SimState) => SimState) {
    setSim(next);
    setChosen(null);
  }

  return (
    <div
      onClickCapture={(event) => {
        countUse(event);
        if (!fromPause(event)) {
          stopDemo();
        }
      }}
      onKeyDown={(event) => {
        // Enter and Space reach the demo as a click.
        if (!fromPause(event) && event.key !== 'Enter' && event.key !== ' ') {
          stopDemo();
        }
      }}
      ref={ref}
      {...props(styles.root)}
    >
      <div {...props(styles.top)}>
        <div {...props(styles.head)}>
          <h3 {...props(styles.label)}>{m.demo_try()}</h3>
          {!lessMotion && (
            <Playing
              fill={fill}
              live={playing}
              on={demoing}
              onToggle={() => {
                if (demoing) {
                  stopDemo();
                  return;
                }
                setSim((state) => preset(state, demoStep(0).preset));
                setCue(DEMO_START);
                setAutoplay(true);
              }}
              ref={pauseRef}
            />
          )}
        </div>
        <div data-scroller {...props(styles.chips)}>
          {PRESETS.map((entry) => (
            <button
              aria-pressed={marked === entry.id}
              data-demo={`preset-${entry.id}`}
              key={entry.id}
              onClick={() => {
                setSim((state) => preset(state, entry.id));
                setChosen(entry.id);
              }}
              type="button"
              {...props(styles.chip, marked === entry.id && styles.chipOn)}
            >
              {entry.title}
            </button>
          ))}
        </div>
        {/* The point of the chosen situation. The room stays when the reader sets things by hand, so nothing below moves. */}
        <p {...props(styles.caption)}>{caption}</p>
      </div>
      <div {...props(styles.grid)}>
        <div {...props(styles.controls)}>
          <div {...props(styles.column)}>
            <h3 {...props(styles.label)}>{m.demo_set_yourself()}</h3>
            <ul {...props(styles.agents)}>
              {AGENTS.map((agent, index) => {
                const now = choiceOf(sim, agent.id);
                return (
                  <li key={agent.id} {...props(styles.agent, index > 0 && styles.agentAfter)}>
                    <span {...props(styles.agentName)}>
                      <AgentIcon name={agent.icon} style={styles.agentIcon} />
                      <span {...props(styles.truncate)}>{agent.name}</span>
                    </span>
                    <Segmented label={m.demo_agent_does({ agent: agent.name })}>
                      {choices().map((entry) => (
                        <button
                          aria-label={m.demo_set_agent({ agent: agent.name, state: entry.spoken })}
                          aria-pressed={now === entry.choice}
                          data-demo={`${entry.choice}-${agent.id}`}
                          key={entry.choice}
                          onClick={() =>
                            change((state) => setChoice(state, agent.id, entry.choice))
                          }
                          type="button"
                          {...props(styles.segment, now === entry.choice && styles.segmentOn)}
                        >
                          {entry.title}
                        </button>
                      ))}
                    </Segmented>
                  </li>
                );
              })}
            </ul>
          </div>
          <div {...props(styles.column)}>
            <Setting label={m.demo_power()}>
              {(['adapter', 'battery'] as const).map((power) => (
                <button
                  aria-pressed={sim.power === power}
                  data-demo={`power-${power}`}
                  key={power}
                  onClick={() => change((state) => setPower(state, power))}
                  type="button"
                  {...props(styles.segment, sim.power === power && styles.segmentOn)}
                >
                  {power === 'adapter' ? m.demo_power_adapter() : m.demo_power_battery()}
                </button>
              ))}
            </Setting>
            <Setting label={m.demo_lid()}>
              {(['open', 'closed'] as const).map((lid) => (
                <button
                  aria-pressed={sim.lid === lid}
                  data-demo={`lid-${lid}`}
                  key={lid}
                  onClick={() => change((state) => setLid(state, lid))}
                  type="button"
                  {...props(styles.segment, sim.lid === lid && styles.segmentOn)}
                >
                  {lid === 'open' ? m.demo_lid_open() : m.demo_lid_closed()}
                </button>
              ))}
            </Setting>
            <div {...props(styles.fades, !onBattery && styles.dimmed)}>
              <Setting label={m.demo_battery_level()}>
                {BATTERY_LEVELS.map((level) => (
                  <button
                    aria-pressed={onBattery && sim.battery === level}
                    data-demo={`battery-${level}`}
                    disabled={!onBattery}
                    key={level}
                    onClick={() => change((state) => setBattery(state, level))}
                    type="button"
                    {...props(
                      styles.segment,
                      styles.tabular,
                      onBattery && sim.battery === level && styles.segmentOn,
                    )}
                  >
                    {level}%
                  </button>
                ))}
              </Setting>
            </div>
          </div>
          <p {...props(styles.note)}>{m.demo_time_note()}</p>
        </div>
        <div {...props(styles.machine)}>
          <div {...props(styles.menuBar)}>
            {GLYPHS.map((width, index) => (
              <span aria-hidden="true" key={index} {...props(styles.glyph)}>
                <span {...props(styles.glyphBar)} style={{ width }} />
              </span>
            ))}
            <span aria-label={shown.iconLabel} role="img" {...props(styles.icon)}>
              {flips > 0 && (
                <span
                  aria-hidden="true"
                  key={flips}
                  {...sceneProps(['demo-pulse'], styles.pulse)}
                />
              )}
              <MenuIcon look={shown.look} style={styles.iconGlyph} />
            </span>
            <span aria-hidden="true" {...props(styles.clock)}>
              {shown.clock}
            </span>
          </div>
          <div {...props(styles.panel)}>
            <AgentsPanel
              enabled={sim.enabled}
              mode={sim.mode}
              onDismiss={() => change(dismissHint)}
              onEnabled={(enabled) => change((state) => setEnabled(state, enabled))}
              onHelper={() => change(allowHelper)}
              onMode={(mode) => change((state) => setMode(state, mode))}
              onPause={(choice) => change((state) => startPause(state, choice))}
              onReachable={(choice) => change((state) => startReachable(state, choice))}
              onResume={() => change(resume)}
              onStopReachable={() => change(stopReachable)}
              paused={!seen || hidden}
              view={shown}
            />
          </div>
          <p aria-atomic="true" aria-live={demoing ? 'off' : 'polite'} {...props(styles.srOnly)}>
            {`${shown.title}. ${shown.subtitle}`}
          </p>
        </div>
      </div>
      {demoing && wide && ring !== null && (
        <span
          aria-hidden="true"
          key={ring.id}
          {...props(styles.pointer)}
          style={{ transform: `translate(${ring.at.x}px, ${ring.at.y}px)` }}
        >
          <span {...sceneProps(['demo-ring'], styles.ring)} />
        </span>
      )}
      {demoing && wide && point !== null && <Pointer at={point} pressing={cue.phase === 'press'} />}
    </div>
  );
}
