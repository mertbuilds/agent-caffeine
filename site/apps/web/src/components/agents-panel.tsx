import { colors, motion as tokens } from '@caffeinagent/ui/tokens.stylex';
import NumberFlow from '@number-flow/react';
import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import { AnimatePresence, motion } from 'motion/react';
import {
  Fragment,
  useEffect,
  useId,
  useRef,
  useState,
  type FocusEvent,
  type KeyboardEvent,
  type ReactNode,
} from 'react';
import { duration, easing } from '../lib/motion.ts';
import { sceneProps } from '../lib/scene-props.ts';
import {
  MODES,
  PAUSES,
  REACHABLES,
  type Attention,
  type Bar,
  type Battery,
  type Child,
  type Group,
  type Mode,
  type PauseChoice,
  type ReachableChoice,
  type View,
  type WorkState,
} from '../lib/simulator.ts';
import { useLessMotion } from '../lib/use-less-motion.ts';
import { m } from '../paraglide/messages.js';
import { AgentIcon, type AgentIconName } from './agent-icons.tsx';
import { Robot } from './robot.tsx';

/**
 * The app's menu, with the measures of `UI/Panel/PanelMetrics.swift`: 320
 * points wide, a 16 point gutter, a 56 point tile for the robot, a 28 point box for an agent's mark in a 34
 * point slot for its ring, and the system's text sizes (17, 13 and 12).
 */

const SYSTEM_FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const ROLL = { duration: 350, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' };
const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';
const TAILWIND_EASE = 'cubic-bezier(0.4, 0, 0.2, 1)';
const RED = 'light-dark(#ff3b30, #ff453a)';
const WARNING = '#ff9500';

export const panelStyles = create({
  divider: {
    backgroundColor: colors.panelLine,
    height: '1px',
  },
  muted: {
    color: colors.panelMuted,
  },
  small: {
    fontSize: '12px',
  },
  spacer: {
    flex: '1 1 0%',
  },
  tabular: {
    fontVariantNumeric: 'tabular-nums',
  },
  truncate: {
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
});

const styles = create({
  activeItem: {
    backgroundColor: colors.appBlue,
    color: 'white',
  },
  attention: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 7%, transparent)`,
    borderRadius: '0.5rem',
    columnGap: '0.5rem',
    display: 'flex',
    flexWrap: 'wrap',
    fontSize: '12px',
    justifyContent: 'space-between',
    lineHeight: '1rem',
    paddingBlock: '0.375rem',
    paddingInline: '0.625rem',
    rowGap: '0.25rem',
    textAlign: 'left',
  },
  attentionActions: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.625rem',
  },
  attentionGlyph: {
    alignItems: 'center',
    display: 'flex',
    height: '1rem',
  },
  attentionSafety: {
    backgroundColor: `color-mix(in srgb, ${WARNING} 12%, transparent)`,
  },
  attentionText: {
    alignItems: 'flex-start',
    display: 'flex',
    gap: '0.375rem',
  },
  bar: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.5rem',
    paddingBlock: '0.5rem',
    paddingInline: '1rem',
  },
  batteryBody: {
    borderRadius: '3px',
    borderWidth: '1px',
    display: 'flex',
    height: '0.625rem',
    padding: '1px',
    width: '1.25rem',
  },
  batteryCap: {
    borderBottomRightRadius: '1px',
    borderTopRightRadius: '1px',
    height: '0.25rem',
    width: '1.5px',
  },
  batteryColors: {
    transitionDuration: '350ms',
    transitionProperty: {
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
      [LESS_MOTION]: 'none',
    },
    transitionTimingFunction: tokens.easeSmoothOut,
  },
  batteryDot: {
    color: `color-mix(in srgb, ${colors.panelFg} 30%, transparent)`,
  },
  batteryGlyph: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    gap: '1px',
  },
  batteryLevel: {
    display: 'block',
    height: '100%',
    transitionDuration: '350ms',
    transitionProperty: { default: 'width, background-color', [LESS_MOTION]: 'none' },
    transitionTimingFunction: tokens.easeSmoothOut,
  },
  batteryLine: {
    alignItems: 'center',
    display: 'flex',
    gap: '5px',
    whiteSpace: 'nowrap',
  },
  batteryWell: {
    borderRadius: '1px',
    flex: '1 1 0%',
    overflow: 'hidden',
  },
  batteryWrap: {
    display: 'flex',
    paddingTop: '0.25rem',
  },
  check: {
    height: '0.5rem',
    width: '0.625rem',
  },
  checkSlot: {
    display: 'flex',
    flexShrink: 0,
    width: '1rem',
  },
  chevron: {
    flexShrink: 0,
    height: '0.625rem',
    width: '0.625rem',
  },
  chevronOpen: {
    transform: 'rotate(90deg)',
  },
  child: {
    alignItems: 'center',
    display: 'flex',
    height: '1.5rem',
    paddingLeft: '42px',
  },
  childLabel: {
    flex: '1 1 0%',
    minWidth: 0,
  },
  childOneLine: {
    gap: '0.75rem',
  },
  children: {
    paddingBottom: '0.25rem',
  },
  childTwoLines: {
    alignItems: 'normal',
    flexDirection: 'column',
    height: '2.5rem',
    justifyContent: 'center',
    lineHeight: '1rem',
  },
  dismiss: {
    alignItems: 'center',
    display: 'flex',
    height: '1rem',
    justifyContent: 'center',
    width: '1rem',
  },
  dismissGlyph: {
    height: '0.5rem',
    width: '0.5rem',
  },
  empty: {
    fontSize: '12px',
    paddingBlock: '1.25rem',
    paddingInline: '1.5rem',
    textAlign: 'center',
    textWrap: 'pretty',
  },
  fade: {
    display: 'grid',
  },
  fadeItem: {
    gridArea: '1 / 1',
  },
  gear: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    height: '1.75rem',
    justifyContent: 'center',
    width: '1.75rem',
  },
  glyph: {
    height: '1rem',
    width: '1rem',
  },
  groupBelow: {
    display: 'flex',
    flex: '1 1 0%',
    flexDirection: 'column',
    gap: '1px',
    lineHeight: '1rem',
    minWidth: 0,
  },
  groupRow: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.5rem',
  },
  groupRowBelow: {
    height: '2.75rem',
  },
  groupRowTrailing: {
    height: '2.25rem',
  },
  groupTitle: {
    flex: '1 1 0%',
    minWidth: 0,
  },
  head: {
    display: 'flex',
    flexDirection: 'column',
    padding: '1rem',
  },
  headRow: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.75rem',
  },
  headText: {
    display: 'flex',
    flex: '1 1 0%',
    flexDirection: 'column',
    minWidth: 0,
  },
  height: {
    overflow: 'hidden',
  },
  item: {
    alignItems: 'center',
    borderRadius: '5px',
    cursor: 'default',
    display: 'flex',
    height: '1.5rem',
    paddingInline: '0.625rem',
  },
  list: {
    display: 'flex',
    flexDirection: 'column',
    paddingBlock: '0.5rem',
    paddingInline: '13px',
    position: 'relative',
  },
  mark: {
    alignItems: 'center',
    display: 'flex',
    flexShrink: 0,
    height: '34px',
    justifyContent: 'center',
    position: 'relative',
    width: '34px',
  },
  markBox: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 8%, transparent)`,
    borderRadius: '0.5rem',
    display: 'flex',
    height: '1.75rem',
    justifyContent: 'center',
    transitionDuration: tokens.durationFast,
    transitionProperty: { default: 'opacity', [LESS_MOTION]: 'none' },
    transitionTimingFunction: TAILWIND_EASE,
    width: '1.75rem',
  },
  markIcon: {
    height: '18px',
    width: '18px',
  },
  markIdle: {
    opacity: 0.55,
  },
  menu: {
    backgroundColor: colors.panel,
    borderColor: colors.panelLine,
    borderRadius: '10px',
    borderWidth: '1px',
    bottom: '100%',
    boxShadow: `0 8px 24px ${colors.shadow}`,
    marginBottom: '0.25rem',
    outline: 'none',
    padding: '5px',
    position: 'absolute',
    whiteSpace: 'nowrap',
    zIndex: 10,
  },
  menuLeft: {
    left: '-0.5rem',
    transformOrigin: 'bottom left',
  },
  menuRight: {
    right: '-52px',
    transformOrigin: 'bottom right',
  },
  modeButton: {
    alignItems: 'center',
    borderRadius: '0.375rem',
    display: 'flex',
    gap: '0.25rem',
    height: '1.75rem',
    marginInline: '-0.375rem',
    paddingInline: '0.375rem',
  },
  modeChevron: {
    height: '0.5rem',
    width: '0.5rem',
  },
  modeItem: {
    paddingLeft: '0.375rem',
    paddingRight: '0.75rem',
  },
  panel: {
    boxShadow: `0 12px 32px ${colors.shadow}`,
    display: 'flex',
    flexDirection: 'column',
    width: '100%',
  },
  picker: {
    position: 'relative',
  },
  pretty: {
    textWrap: 'pretty',
  },
  ring: {
    height: '100%',
    inset: 0,
    position: 'absolute',
    width: '100%',
  },
  safetyGlyph: {
    color: WARNING,
    height: '0.75rem',
    width: '0.75rem',
  },
  separator: {
    backgroundColor: colors.panelLine,
    height: '1px',
    marginBlock: '5px',
    marginInline: '0.625rem',
  },
  setUp: {
    color: colors.accent,
  },
  shrink: {
    flexShrink: 0,
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
  subtitle: {
    marginTop: '0.125rem',
    textWrap: 'pretty',
  },
  surface: {
    backgroundColor: colors.panel,
    borderColor: colors.panelLine,
    borderRadius: '0.75rem',
    borderWidth: '1px',
    color: colors.panelFg,
    fontFamily: SYSTEM_FONT,
    fontSize: '13px',
    lineHeight: '1rem',
    textAlign: 'left',
  },
  switch: {
    alignItems: 'center',
    backgroundColor: `color-mix(in srgb, ${colors.panelFg} 20%, transparent)`,
    borderRadius: '9999px',
    display: 'flex',
    flexShrink: 0,
    height: '1.25rem',
    padding: '0.125rem',
    transitionDuration: tokens.durationFast,
    transitionProperty: {
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
      [LESS_MOTION]: 'none',
    },
    transitionTimingFunction: tokens.easeSmoothOut,
    width: '2.75rem',
  },
  switchKnob: {
    backgroundColor: 'white',
    borderRadius: '9999px',
    boxShadow: '0 1px 2px rgba(0, 0, 0, 0.25)',
    height: '1rem',
    transform: 'translateX(0)',
    transitionDuration: tokens.durationFast,
    transitionProperty: { default: 'transform', [LESS_MOTION]: 'none' },
    transitionTimingFunction: tokens.easeSmoothOut,
    width: '26px',
  },
  switchKnobOn: {
    transform: 'translateX(14px)',
  },
  switchOn: {
    backgroundColor: colors.appBlue,
  },
  terminal: {
    height: '0.875rem',
    width: '0.875rem',
  },
  timed: {
    alignItems: 'center',
    color: colors.accent,
    display: 'flex',
    flexShrink: 0,
    height: '1.75rem',
  },
  timedLabel: {
    minWidth: 0,
  },
  timerButton: {
    alignItems: 'center',
    borderRadius: '0.375rem',
    display: 'flex',
    height: '1.75rem',
    justifyContent: 'center',
    width: '1.75rem',
  },
  title: {
    fontSize: '17px',
    lineHeight: '22px',
  },
  topGap: {
    paddingTop: '0.75rem',
  },
  windowGlyph: {
    height: '0.75rem',
    width: '0.875rem',
  },
});

/** Text whose numbers roll when they change, as the app's do. A group of digits keeps its length, so "06:00" keeps its zeros. With `still` a change shows at once. */
export function Flow({ children, still = false }: { children: string; still?: boolean }) {
  return (
    <>
      {children
        .split(/(\d+)/)
        .map((part, index) =>
          index % 2 === 1 ? (
            <NumberFlow
              animated={!still}
              className={props(panelStyles.tabular).className}
              format={{ minimumIntegerDigits: part.length }}
              key={index}
              locales="en-US"
              opacityTiming={ROLL}
              spinTiming={ROLL}
              transformTiming={ROLL}
              value={Number(part)}
            />
          ) : (
            <Fragment key={index}>{part}</Fragment>
          ),
        )}
    </>
  );
}

/** The same text whatever its numbers are, to key a line that should not come in again when only a number changes. */
function shape(text: string): string {
  return text.replaceAll(/\d+/g, '0');
}

/** The ring round an agent's mark: an arc that goes round for work, a whole amber ring that breathes for an agent that waits, none when idle. */
function StateRing({ state }: { state: WorkState }) {
  if (state === 'idle') {
    return null;
  }
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 34 34" {...props(styles.ring)}>
      <rect
        className={state === 'working' ? 'ring-sweep' : 'ring-breathe'}
        height="32.5"
        pathLength="1"
        rx="10.25"
        stroke={state === 'working' ? 'var(--app-blue)' : 'var(--app-amber)'}
        strokeDasharray={state === 'working' ? '0.75 0.25' : undefined}
        strokeLinecap="round"
        strokeWidth="1.5"
        width="32.5"
        x="0.75"
        y="0.75"
      />
    </svg>
  );
}

/** An agent's mark in its box. With no mark it is the plain terminal glyph of `AgentLogoView.swift`, as for a hold from the command line. */
export function AgentMark({ icon, state }: { icon: AgentIconName | null; state: WorkState }) {
  return (
    <span {...props(styles.mark)}>
      <span {...props(styles.markBox, state === 'idle' && styles.markIdle)}>
        {icon === null ? (
          <svg
            aria-hidden="true"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.4"
            viewBox="0 0 16 16"
            {...props(styles.terminal, panelStyles.muted)}
          >
            <rect height="11" rx="2.5" width="13" x="1.5" y="2.5" />
            <path d="m4.5 6 2.25 2L4.5 10M8.5 10.25h3" />
          </svg>
        ) : (
          <AgentIcon name={icon} style={styles.markIcon} />
        )}
      </span>
      <StateRing state={state} />
    </span>
  );
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.6"
      viewBox="0 0 10 10"
      {...props(styles.chevron, panelStyles.muted, open && styles.chevronOpen)}
    >
      <path d="M3.5 1.5 7 5 3.5 8.5" />
    </svg>
  );
}

function ChildRow({ child, layout }: { child: Child; layout: Group['layout'] }) {
  if (child.detail === null) {
    return <li {...props(styles.child, panelStyles.small, panelStyles.muted)}>{child.label}</li>;
  }
  return layout === 'oneLine' ? (
    <li {...props(styles.child, styles.childOneLine, panelStyles.small)}>
      <span {...props(styles.childLabel, panelStyles.truncate)}>{child.label}</span>
      <span {...props(styles.shrink, panelStyles.muted)}>
        <Flow>{child.detail}</Flow>
      </span>
    </li>
  ) : (
    <li {...props(styles.child, styles.childTwoLines, panelStyles.small)}>
      <span {...props(panelStyles.truncate)}>{child.label}</span>
      <span {...props(panelStyles.truncate, panelStyles.muted)}>
        <Flow>{child.detail}</Flow>
      </span>
    </li>
  );
}

/** One agent: its line, and its sessions below it when the group is open. */
export function GroupRows({ group }: { group: Group }) {
  const idle = group.state === 'idle';
  const trailing = group.place === 'trailing';
  const detail = (
    <span {...props(panelStyles.small, panelStyles.muted)}>
      <Flow>{group.detail}</Flow>
    </span>
  );
  return (
    <>
      <div {...props(styles.groupRow, trailing ? styles.groupRowTrailing : styles.groupRowBelow)}>
        <AgentMark icon={group.icon} state={group.state} />
        {trailing ? (
          <>
            <span {...props(styles.groupTitle, panelStyles.truncate, idle && panelStyles.muted)}>
              {group.title}
            </span>
            <span {...props(styles.shrink)}>{detail}</span>
          </>
        ) : (
          <span {...props(styles.groupBelow)}>
            <span {...props(panelStyles.truncate)}>{group.title}</span>
            <span {...props(panelStyles.truncate)}>{detail}</span>
          </span>
        )}
        {group.open !== null && <Chevron open={group.open} />}
      </div>
      {group.open === true && group.children.length > 0 && (
        <ul {...props(styles.children)}>
          {group.children.map((child) => (
            <ChildRow child={child} key={child.key} layout={group.layout} />
          ))}
        </ul>
      )}
    </>
  );
}

/** Closes a menu when the focus leaves it and its button. */
function closesOnLeave(close: () => void) {
  return (event: FocusEvent<HTMLUListElement>) => {
    const to = event.relatedTarget;
    if (to === null || event.currentTarget.parentElement?.contains(to) !== true) {
      close();
    }
  };
}

/** The mode in the bar at the bottom: its short name, and a menu with the whole names. */
function ModePicker({ mode, onChange }: { mode: Mode; onChange: (mode: Mode) => void }) {
  const id = useId();
  const lessMotion = useLessMotion();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const selected = Math.max(
    0,
    MODES.findIndex((entry) => entry.mode === mode),
  );
  const [active, setActive] = useState(selected);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (open) {
      listRef.current?.focus();
    }
  }, [open]);

  function show() {
    setActive(selected);
    setOpen(true);
  }

  function close() {
    setOpen(false);
    buttonRef.current?.focus();
  }

  function choose(index: number) {
    const entry = MODES[index];
    if (entry !== undefined) {
      onChange(entry.mode);
    }
    close();
  }

  function onButtonKey(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      show();
    }
  }

  function onListKey(event: KeyboardEvent<HTMLUListElement>) {
    const moves: Record<string, number> = {
      ArrowDown: Math.min(active + 1, MODES.length - 1),
      ArrowUp: Math.max(active - 1, 0),
      End: MODES.length - 1,
      Home: 0,
    };
    const move = moves[event.key];
    if (move !== undefined) {
      event.preventDefault();
      setActive(move);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      choose(active);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === 'Tab') {
      setOpen(false);
    }
  }

  return (
    <div {...props(styles.picker)}>
      <span id={`${id}-label`} {...props(styles.srOnly)}>
        {m.panel_mode_label()}
      </span>
      <button
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-labelledby={`${id}-label ${id}-button`}
        data-demo="mode"
        id={`${id}-button`}
        onClick={() => (open ? setOpen(false) : show())}
        onKeyDown={onButtonKey}
        ref={buttonRef}
        type="button"
        {...props(styles.modeButton)}
      >
        {MODES[selected]?.short}
        <svg
          aria-hidden="true"
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="1.5"
          viewBox="0 0 8 8"
          {...props(styles.modeChevron, panelStyles.muted)}
        >
          <path d="M1.5 3 4 5.5 6.5 3" />
        </svg>
      </button>
      <AnimatePresence>
        {open && (
          <motion.ul
            animate={{ opacity: 1, scale: 1 }}
            aria-activedescendant={`${id}-option-${active}`}
            aria-labelledby={`${id}-label`}
            className={props(styles.menu, styles.menuLeft).className}
            exit={{
              opacity: 0,
              scale: 0.97,
              transition: { duration: lessMotion ? 0 : duration.quick, ease: easing.smoothOut },
            }}
            initial={lessMotion ? false : { opacity: 0, scale: 0.97 }}
            key="menu"
            onBlur={closesOnLeave(() => setOpen(false))}
            onKeyDown={onListKey}
            ref={listRef}
            role="listbox"
            tabIndex={-1}
            transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
          >
            {MODES.map((entry, index) => (
              <li
                aria-selected={index === selected}
                data-demo={`mode-${entry.mode}`}
                id={`${id}-option-${index}`}
                key={entry.mode}
                onClick={() => choose(index)}
                onMouseMove={() => setActive(index)}
                role="option"
                {...props(styles.item, styles.modeItem, index === active && styles.activeItem)}
              >
                <span aria-hidden="true" {...props(styles.checkSlot)}>
                  {index === selected && (
                    <svg
                      fill="none"
                      stroke="currentColor"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="1.5"
                      viewBox="0 0 10 8"
                      {...props(styles.check)}
                    >
                      <path d="M1 4.2 3.8 7 9 1" />
                    </svg>
                  )}
                </span>
                {entry.title}
              </li>
            ))}
          </motion.ul>
        )}
      </AnimatePresence>
    </div>
  );
}

export function Gear() {
  return (
    <span aria-hidden="true" {...props(styles.gear, panelStyles.muted)}>
      <svg
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
        viewBox="0 0 24 24"
        {...props(styles.glyph)}
      >
        <path d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
        <path d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
      </svg>
    </span>
  );
}

/** The timer of the bar at the bottom: a dial with a mark at the top and one hand. */
function TimerGlyph() {
  return (
    <svg
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.5"
      viewBox="0 0 24 24"
      {...props(styles.glyph)}
    >
      <path d="M12 3.25a8.75 8.75 0 1 1-6.19 2.56" />
      <path d="M12 3.25v3M12 12 8.2 8.2" />
    </svg>
  );
}

/** The choices of the timer menu, in the order of the app: a pause, then its mirror. */
export function TimerChoices({
  active = null,
  bar,
  id,
  onActive,
  onPause,
  onReachable,
}: {
  active?: number | null;
  bar: Pick<Bar, 'reachable' | 'reachableCost'>;
  id?: string;
  onActive?: (index: number) => void;
  onPause?: (choice: PauseChoice) => void;
  onReachable?: (choice: ReachableChoice) => void;
}) {
  const item = (index: number, key: string, title: string, choose?: () => void) => (
    <li
      data-demo={key}
      id={id === undefined ? undefined : `${id}-item-${index}`}
      key={key}
      onClick={choose}
      onMouseMove={onActive === undefined ? undefined : () => onActive(index)}
      role="menuitem"
      {...props(styles.item, index === active && styles.activeItem)}
    >
      {title}
    </li>
  );
  return (
    <>
      {PAUSES.map((entry, index) =>
        item(index, `pause-${entry.choice}`, entry.title, onPause && (() => onPause(entry.choice))),
      )}
      {bar.reachable && (
        <>
          <li aria-hidden="true" role="separator" {...props(styles.separator)} />
          {REACHABLES.map((entry, index) =>
            item(
              PAUSES.length + index,
              `reachable-${entry.choice}`,
              entry.title,
              onReachable && (() => onReachable(entry.choice)),
            ),
          )}
          {bar.reachableCost !== null && (
            <li aria-disabled="true" role="menuitem" {...props(styles.item, panelStyles.muted)}>
              {bar.reachableCost}
            </li>
          )}
        </>
      )}
    </>
  );
}

/** The timer button next to the switch: a pause, and its opposite. */
function TimerMenu({
  bar,
  onPause,
  onReachable,
}: {
  bar: Bar;
  onPause: (choice: PauseChoice) => void;
  onReachable: (choice: ReachableChoice) => void;
}) {
  const id = useId();
  const lessMotion = useLessMotion();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const count = PAUSES.length + (bar.reachable ? REACHABLES.length : 0);
  const [active, setActive] = useState<number | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (open) {
      listRef.current?.focus();
    }
  }, [open]);

  function show(first: number | null) {
    setActive(first);
    setOpen(true);
  }

  function close() {
    setOpen(false);
    buttonRef.current?.focus();
  }

  function choose(index: number) {
    setOpen(false);
    const pause = PAUSES[index];
    const reachable = REACHABLES[index - PAUSES.length];
    if (pause !== undefined) {
      onPause(pause.choice);
    } else if (reachable !== undefined) {
      onReachable(reachable.choice);
    }
  }

  function onListKey(event: KeyboardEvent<HTMLUListElement>) {
    const moves: Record<string, number> = {
      ArrowDown: active === null ? 0 : Math.min(active + 1, count - 1),
      ArrowUp: active === null ? count - 1 : Math.max(active - 1, 0),
      End: count - 1,
      Home: 0,
    };
    const move = moves[event.key];
    if (move !== undefined) {
      event.preventDefault();
      setActive(move);
    } else if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      if (active !== null) {
        choose(active);
      }
    } else if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === 'Tab') {
      setOpen(false);
    }
  }

  return (
    <div {...props(styles.picker)}>
      <button
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label={m.panel_timer_label()}
        data-demo="timer"
        onClick={() => (open ? setOpen(false) : show(null))}
        onKeyDown={(event) => {
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            show(event.key === 'ArrowDown' ? 0 : count - 1);
          }
        }}
        ref={buttonRef}
        type="button"
        {...props(styles.timerButton, panelStyles.muted)}
      >
        <TimerGlyph />
      </button>
      <AnimatePresence>
        {open && (
          <motion.ul
            animate={{ opacity: 1, scale: 1 }}
            aria-activedescendant={active === null ? undefined : `${id}-item-${active}`}
            aria-label={m.panel_timer_label()}
            className={props(styles.menu, styles.menuRight).className}
            exit={{
              opacity: 0,
              scale: 0.97,
              transition: { duration: lessMotion ? 0 : duration.quick, ease: easing.smoothOut },
            }}
            initial={lessMotion ? false : { opacity: 0, scale: 0.97 }}
            key="menu"
            onBlur={closesOnLeave(() => setOpen(false))}
            onKeyDown={onListKey}
            ref={listRef}
            role="menu"
            tabIndex={-1}
            transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
          >
            <TimerChoices
              active={active}
              bar={bar}
              id={id}
              onActive={setActive}
              onPause={(choice) => {
                setOpen(false);
                onPause(choice);
              }}
              onReachable={(choice) => {
                setOpen(false);
                onReachable(choice);
              }}
            />
          </motion.ul>
        )}
      </AnimatePresence>
    </div>
  );
}

/** In place of the mode: until when, and the way out. */
function Timed({
  end,
  label,
  name,
  onEnd,
}: {
  end: string;
  label: string;
  name: string;
  onEnd: () => void;
}) {
  return (
    <>
      <span
        {...props(styles.timedLabel, panelStyles.truncate, panelStyles.tabular, panelStyles.muted)}
      >
        {label}
      </span>
      <button data-demo={name} onClick={onEnd} type="button" {...props(styles.timed)}>
        {end}
      </button>
    </>
  );
}

/** The charge of the battery on one line below the headline: a small mark, the number, and what follows from it (`UI/Panel/BatteryLine.swift`). */
export function BatteryLine({ battery }: { battery: Battery }) {
  const quiet = 'var(--panel-muted)';
  const accent =
    battery.level === 'normal' ? quiet : battery.level === 'nearFloor' ? 'var(--app-amber)' : RED;
  const outline = battery.level === 'stopped' ? RED : quiet;
  return (
    <div
      aria-label={battery.spoken}
      role="img"
      {...props(styles.batteryLine, panelStyles.small, panelStyles.tabular, panelStyles.muted)}
    >
      {/* A body of 20 by 10 points with a 1 point outline, the level 1 point inside it, and a cap. */}
      <span aria-hidden="true" {...props(styles.batteryGlyph)}>
        <span {...props(styles.batteryBody, styles.batteryColors)} style={{ borderColor: outline }}>
          <span {...props(styles.batteryWell)}>
            <span
              {...props(styles.batteryLevel)}
              // A battery that is not empty always shows a sliver.
              style={{
                background: accent,
                width: battery.percent > 0 ? `max(1px, ${battery.percent}%)` : 0,
              }}
            />
          </span>
        </span>
        <span {...props(styles.batteryCap, styles.batteryColors)} style={{ background: outline }} />
      </span>
      {battery.charge !== null && (
        <>
          <span aria-hidden="true" {...props(styles.batteryColors)} style={{ color: accent }}>
            <Flow>{battery.charge}</Flow>
          </span>
          <span aria-hidden="true" {...props(styles.batteryDot)}>
            ·
          </span>
        </>
      )}
      <span aria-hidden="true">
        <Flow>{battery.consequence}</Flow>
      </span>
    </div>
  );
}

/** The switch of the app. Without `onChange` it is a still drawing of one state. */
export function Switch({ on, onChange }: { on: boolean; onChange?: (on: boolean) => void }) {
  const knob = <span {...props(styles.switchKnob, on && styles.switchKnobOn)} />;
  if (onChange === undefined) {
    return (
      <span aria-hidden="true" {...props(styles.switch, on && styles.switchOn)}>
        {knob}
      </span>
    );
  }
  return (
    <button
      aria-checked={on}
      aria-label={m.app_name()}
      data-demo="switch"
      onClick={() => onChange(!on)}
      role="switch"
      type="button"
      {...props(styles.switch, on && styles.switchOn)}
    >
      {knob}
    </button>
  );
}

/** The one line below the headline that needs the reader. */
function AttentionLine({
  attention,
  onDismiss,
  onHelper,
}: {
  attention: Attention;
  onDismiss: () => void;
  onHelper: () => void;
}) {
  const safety = attention.kind === 'safetyStop';
  return (
    <div {...props(styles.attention, safety && styles.attentionSafety)}>
      <span {...props(styles.attentionText)}>
        <span aria-hidden="true" {...props(styles.attentionGlyph)}>
          {safety ? (
            <svg fill="currentColor" viewBox="0 0 12 12" {...props(styles.safetyGlyph)}>
              <path
                d="M5.13 1.5a1 1 0 0 1 1.74 0l4.5 8A1 1 0 0 1 10.5 11h-9a1 1 0 0 1-.87-1.5zM6 4.2a.6.6 0 0 0-.6.6v2.4a.6.6 0 0 0 1.2 0V4.8a.6.6 0 0 0-.6-.6zm0 4.4a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4z"
                fillRule="evenodd"
              />
            </svg>
          ) : (
            <svg
              fill="none"
              stroke="currentColor"
              strokeLinejoin="round"
              strokeWidth="1.1"
              viewBox="0 0 14 12"
              {...props(styles.windowGlyph, panelStyles.muted)}
            >
              <rect height="7" rx="1" width="9" x="2.5" y="1.5" />
              <path d="M0.8 10.5h12.4" strokeLinecap="round" />
            </svg>
          )}
        </span>
        <span {...props(styles.pretty)}>{attention.text}</span>
      </span>
      {!safety && (
        <span {...props(styles.attentionActions)}>
          <button data-demo="helper" onClick={onHelper} type="button" {...props(styles.setUp)}>
            {m.panel_set_up()}
          </button>
          {attention.kind === 'lidClosedNotSetUp' && (
            <button
              aria-label={m.panel_dismiss()}
              onClick={onDismiss}
              type="button"
              {...props(styles.dismiss, panelStyles.muted)}
            >
              <svg
                aria-hidden="true"
                fill="none"
                stroke="currentColor"
                strokeLinecap="round"
                strokeWidth="1.5"
                viewBox="0 0 8 8"
                {...props(styles.dismissGlyph)}
              >
                <path d="m1 1 6 6M7 1 1 7" />
              </svg>
            </button>
          )}
        </span>
      )}
    </div>
  );
}

function Fade({
  children,
  id,
  lessMotion,
}: {
  children: ReactNode;
  id: string;
  lessMotion: boolean;
}) {
  return (
    <span {...props(styles.fade)}>
      <AnimatePresence initial={false}>
        <motion.span
          animate={{ opacity: 1 }}
          className={props(styles.fadeItem).className}
          exit={{ opacity: 0 }}
          initial={lessMotion ? false : { opacity: 0 }}
          key={id}
          transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
        >
          {children}
        </motion.span>
      </AnimatePresence>
    </span>
  );
}

/** Animates its height to fit what it holds, so the panel grows and shrinks smoothly. */
function AutoHeight({ children, lessMotion }: { children: ReactNode; lessMotion: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState<number | 'auto'>('auto');

  useEffect(() => {
    const element = ref.current;
    if (element === null) {
      return;
    }
    const observer = new ResizeObserver(() => setHeight(element.offsetHeight));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  return (
    <motion.div
      animate={{ height }}
      className={props(styles.height).className}
      initial={false}
      transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
    >
      <div ref={ref}>{children}</div>
    </motion.div>
  );
}

/**
 * The window of the menu, for the simulator and for a still cut of it. `scenes` are class names of
 * styles/scenes.css, such as `panel-still`, which holds the rings.
 */
export function PanelSurface({
  children,
  label,
  scenes = [],
  style,
}: {
  children: ReactNode;
  label: string;
  scenes?: ReadonlyArray<string | false>;
  style?: StyleXStyles | undefined;
}) {
  return (
    <div aria-label={label} role="group" {...sceneProps(scenes, styles.surface, style)}>
      {children}
    </div>
  );
}

const notificationStyles = create({
  card: {
    alignItems: 'flex-start',
    borderRadius: '1rem',
    boxShadow: `0 8px 24px ${colors.shadow}`,
    display: 'flex',
    gap: '0.625rem',
    padding: '0.625rem',
  },
  icon: {
    flexShrink: 0,
    height: '2rem',
    width: '2rem',
  },
  text: {
    display: 'flex',
    flexDirection: 'column',
    fontSize: '12px',
    gap: '1px',
    lineHeight: '1rem',
    minWidth: 0,
  },
});

/** A notification of the app, as macOS shows it: the app's icon, then its lines. */
export function NotificationCut({
  children,
  label,
  style,
}: {
  children: ReactNode;
  label: string;
  style?: StyleXStyles | undefined;
}) {
  return (
    <PanelSurface label={label} style={[notificationStyles.card, style]}>
      <img
        alt={''}
        height={32}
        loading="lazy"
        src="/icon.png"
        width={32}
        {...props(notificationStyles.icon)}
      />
      <span {...props(notificationStyles.text)}>{children}</span>
    </PanelSurface>
  );
}

type AgentsPanelProps = {
  enabled: boolean;
  mode: Mode;
  onDismiss: () => void;
  onEnabled: (enabled: boolean) => void;
  onHelper: () => void;
  onMode: (mode: Mode) => void;
  onPause: (choice: PauseChoice) => void;
  onReachable: (choice: ReachableChoice) => void;
  onResume: () => void;
  onStopReachable: () => void;
  /** Holds the loops while nobody sees the menu. */
  paused: boolean;
  view: View;
};

export function AgentsPanel({
  enabled,
  mode,
  onDismiss,
  onEnabled,
  onHelper,
  onMode,
  onPause,
  onReachable,
  onResume,
  onStopReachable,
  paused,
  view,
}: AgentsPanelProps) {
  const lessMotion = useLessMotion();
  const move = { duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut };

  return (
    <PanelSurface label={m.panel_label()} scenes={[paused && 'panel-paused']} style={styles.panel}>
      {/* `HeroView.swift` and `PanelView.swift`: the robot on its 56 point tile, 12 points, then the headline and its reason, with the battery below them. What needs the reader is a line of the whole width under that row. */}
      <div {...props(styles.head)}>
        <div {...props(styles.headRow)}>
          <Robot paused={paused} pose={view.pose} size={56} />
          <div {...props(styles.headText)}>
            <p {...props(styles.title)}>
              <Fade id={view.title} lessMotion={lessMotion}>
                {view.title}
              </Fade>
            </p>
            {/* A reason is never cut short: it goes on to a second line. */}
            <p {...props(styles.subtitle, panelStyles.muted)}>
              <Fade id={shape(view.subtitle)} lessMotion={lessMotion}>
                <Flow>{view.subtitle}</Flow>
              </Fade>
            </p>
            <AutoHeight lessMotion={lessMotion}>
              {view.battery !== null && (
                <div {...props(styles.batteryWrap)}>
                  <BatteryLine battery={view.battery} />
                </div>
              )}
            </AutoHeight>
          </div>
        </div>
        <AutoHeight lessMotion={lessMotion}>
          {view.attention !== null && (
            <div {...props(styles.topGap)}>
              <AttentionLine attention={view.attention} onDismiss={onDismiss} onHelper={onHelper} />
            </div>
          )}
        </AutoHeight>
      </div>
      <div {...props(panelStyles.divider)} />
      <AutoHeight lessMotion={lessMotion}>
        {view.emptyText !== null ? (
          <p {...props(styles.empty, panelStyles.muted)}>{view.emptyText}</p>
        ) : (
          <ul {...props(styles.list)}>
            <AnimatePresence initial={false} mode="popLayout">
              {view.groups.map((group) => (
                <motion.li
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  initial={lessMotion ? false : { opacity: 0 }}
                  key={group.agent}
                  layout={lessMotion ? false : 'position'}
                  transition={move}
                >
                  <GroupRows group={group} />
                </motion.li>
              ))}
            </AnimatePresence>
          </ul>
        )}
      </AutoHeight>
      <div {...props(panelStyles.divider)} />
      <div {...props(styles.bar)}>
        {view.bar.pausedLabel !== null ? (
          <Timed
            end={m.panel_resume()}
            label={view.bar.pausedLabel}
            name="resume"
            onEnd={onResume}
          />
        ) : view.bar.reachableLabel !== null ? (
          <Timed
            end={m.panel_stop()}
            label={view.bar.reachableLabel}
            name="stop"
            onEnd={onStopReachable}
          />
        ) : (
          <ModePicker mode={mode} onChange={onMode} />
        )}
        <span {...props(panelStyles.spacer)} />
        <Gear />
        {view.bar.timer && <TimerMenu bar={view.bar} onPause={onPause} onReachable={onReachable} />}
        <Switch on={enabled} onChange={onEnabled} />
      </div>
    </PanelSurface>
  );
}
