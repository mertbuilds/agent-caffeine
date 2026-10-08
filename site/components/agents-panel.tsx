"use client";

import NumberFlow from "@number-flow/react";
import { AnimatePresence, motion } from "motion/react";
import { Fragment, useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { Robot } from "@/components/robot";
import { duration, easing } from "@/lib/motion";
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
} from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";

/**
 * The app's menu, with the measures of `UI/Panel/PanelMetrics.swift`: 320
 * points wide, a 16 point gutter, a 28 point box for an agent's mark in a 34
 * point slot for its ring, and the system's text sizes (17, 13 and 12).
 */

const SYSTEM_FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const FG = "text-[var(--panel-fg)]";
const MUTED = "text-[var(--panel-muted)]";
const ROLL = { duration: 350, easing: "cubic-bezier(0.22, 1, 0.36, 1)" };

/** Text whose numbers roll when they change, as the app's do. A group of digits keeps its length, so "06:00" keeps its zeros. */
export function Flow({ children }: { children: string }) {
  return (
    <>
      {children.split(/(\d+)/).map((part, index) =>
        index % 2 === 1 ? (
          <NumberFlow
            key={index}
            className="tabular-nums"
            format={{ minimumIntegerDigits: part.length }}
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
  return text.replace(/\d+/g, "0");
}

/** The ring round an agent's mark: an arc that goes round for work, a whole amber ring that breathes for an agent that waits, none when idle. */
function StateRing({ state }: { state: WorkState }) {
  if (state === "idle") {
    return null;
  }
  return (
    <svg aria-hidden="true" className="absolute inset-0 size-full" fill="none" viewBox="0 0 34 34">
      <rect
        className={state === "working" ? "ring-sweep" : "ring-breathe"}
        height="32.5"
        pathLength="1"
        rx="10.25"
        stroke={state === "working" ? "var(--app-blue)" : "var(--app-amber)"}
        strokeDasharray={state === "working" ? "0.75 0.25" : undefined}
        strokeLinecap="round"
        strokeWidth="1.5"
        width="32.5"
        x="0.75"
        y="0.75"
      />
    </svg>
  );
}

function AgentMark({ icon, state }: { icon: AgentIconName; state: WorkState }) {
  return (
    <span className="relative flex size-[34px] shrink-0 items-center justify-center">
      <span
        className={`flex size-7 items-center justify-center rounded-lg bg-[color-mix(in_srgb,var(--panel-fg)_8%,transparent)] transition-opacity duration-fast motion-reduce:transition-none ${state === "idle" ? "opacity-55" : ""}`}
      >
        <AgentIcon className="size-[18px]" name={icon} />
      </span>
      <StateRing state={state} />
    </span>
  );
}

function Chevron({ open }: { open: boolean }) {
  return (
    <svg
      aria-hidden="true"
      className={`h-2.5 w-2.5 shrink-0 ${MUTED} ${open ? "rotate-90" : ""}`}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.6"
      viewBox="0 0 10 10"
    >
      <path d="M3.5 1.5 7 5 3.5 8.5" />
    </svg>
  );
}

function ChildRow({ child, layout }: { child: Child; layout: Group["layout"] }) {
  if (child.detail === null) {
    return <li className={`flex h-6 items-center pl-[42px] text-[12px] ${MUTED}`}>{child.label}</li>;
  }
  return layout === "oneLine" ? (
    <li className="flex h-6 items-center gap-3 pl-[42px] text-[12px]">
      <span className="min-w-0 flex-1 truncate">{child.label}</span>
      <span className={`shrink-0 ${MUTED}`}>
        <Flow>{child.detail}</Flow>
      </span>
    </li>
  ) : (
    <li className="flex h-10 flex-col justify-center pl-[42px] text-[12px] leading-4">
      <span className="truncate">{child.label}</span>
      <span className={`truncate ${MUTED}`}>
        <Flow>{child.detail}</Flow>
      </span>
    </li>
  );
}

/** One agent: its line, and its sessions below it when the group is open. */
export function GroupRows({ group }: { group: Group }) {
  const idle = group.state === "idle";
  const detail = (
    <span className={`text-[12px] ${MUTED}`}>
      <Flow>{group.detail}</Flow>
    </span>
  );
  return (
    <>
      <div className={`flex items-center gap-2 ${group.place === "trailing" ? "h-9" : "h-11"}`}>
        <AgentMark icon={group.icon} state={group.state} />
        {group.place === "trailing" ? (
          <>
            <span className={`min-w-0 flex-1 truncate ${idle ? MUTED : ""}`}>{group.title}</span>
            <span className="shrink-0">{detail}</span>
          </>
        ) : (
          <span className="flex min-w-0 flex-1 flex-col gap-px leading-4">
            <span className="truncate">{group.title}</span>
            <span className="truncate">{detail}</span>
          </span>
        )}
        {group.open !== null && <Chevron open={group.open} />}
      </div>
      {group.open === true && group.children.length > 0 && (
        <ul className="pb-1">
          {group.children.map((child) => (
            <ChildRow key={child.key} child={child} layout={group.layout} />
          ))}
        </ul>
      )}
    </>
  );
}

/** The mode in the bar at the bottom: its short name, and a menu with the whole names. */
function ModePicker({ mode, onChange }: { mode: Mode; onChange: (mode: Mode) => void }) {
  const id = useId();
  const lessMotion = useLessMotion();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLUListElement>(null);
  const selected = Math.max(0, MODES.findIndex((entry) => entry.mode === mode));
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
    onChange(MODES[index].mode);
    close();
  }

  function onButtonKey(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      show();
    }
  }

  function onListKey(event: KeyboardEvent<HTMLUListElement>) {
    const moves: Record<string, number> = {
      ArrowDown: Math.min(active + 1, MODES.length - 1),
      ArrowUp: Math.max(active - 1, 0),
      Home: 0,
      End: MODES.length - 1,
    };
    if (event.key in moves) {
      event.preventDefault();
      setActive(moves[event.key]);
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      choose(active);
    } else if (event.key === "Escape") {
      event.preventDefault();
      close();
    } else if (event.key === "Tab") {
      setOpen(false);
    }
  }

  return (
    <div className="relative">
      <span className="sr-only" id={`${id}-label`}>
        Keep your Mac awake
      </span>
      <button
        ref={buttonRef}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-labelledby={`${id}-label ${id}-button`}
        className="-mx-1.5 flex h-7 items-center gap-1 rounded-md px-1.5"
        data-demo="mode"
        id={`${id}-button`}
        onClick={() => (open ? setOpen(false) : show())}
        onKeyDown={onButtonKey}
        type="button"
      >
        {MODES[selected].short}
        <svg
          aria-hidden="true"
          className={`h-2 w-2 ${MUTED}`}
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="1.5"
          viewBox="0 0 8 8"
        >
          <path d="M1.5 3 4 5.5 6.5 3" />
        </svg>
      </button>
      <AnimatePresence>
        {open && (
          <motion.ul
            key="menu"
            ref={listRef}
            animate={{ opacity: 1, scale: 1 }}
            aria-activedescendant={`${id}-option-${active}`}
            aria-labelledby={`${id}-label`}
            className="absolute -left-2 bottom-full z-10 mb-1 origin-bottom-left whitespace-nowrap rounded-[10px] border border-[var(--panel-line)] bg-[var(--panel)] p-[5px] shadow-[0_8px_24px_var(--shadow)] outline-none"
            exit={{ opacity: 0, scale: 0.97, transition: { duration: lessMotion ? 0 : duration.quick, ease: easing.smoothOut } }}
            initial={lessMotion ? false : { opacity: 0, scale: 0.97 }}
            onBlur={(event) => {
              const to = event.relatedTarget;
              if (!(to instanceof Node && event.currentTarget.parentElement?.contains(to))) {
                setOpen(false);
              }
            }}
            onKeyDown={onListKey}
            role="listbox"
            tabIndex={-1}
            transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
          >
            {MODES.map((entry, index) => (
              <li
                key={entry.mode}
                aria-selected={index === selected}
                className={`flex h-6 cursor-default items-center rounded-[5px] pl-1.5 pr-3 ${index === active ? "bg-[var(--app-blue)] text-white" : ""}`}
                data-demo={`mode-${entry.mode}`}
                id={`${id}-option-${index}`}
                onClick={() => choose(index)}
                onMouseMove={() => setActive(index)}
                role="option"
              >
                <span aria-hidden="true" className="flex w-4 shrink-0">
                  {index === selected && (
                    <svg
                      className="h-2 w-2.5"
                      fill="none"
                      stroke="currentColor"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="1.5"
                      viewBox="0 0 10 8"
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
    <span aria-hidden="true" className={`flex size-7 shrink-0 items-center justify-center ${MUTED}`}>
      <svg className="size-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" viewBox="0 0 24 24">
        <path d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
        <path d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
      </svg>
    </span>
  );
}

/** The timer of the bar at the bottom: a dial with a mark at the top and one hand. */
export function TimerGlyph() {
  return (
    <svg aria-hidden="true" className="size-4" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5" viewBox="0 0 24 24">
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
  bar: Pick<Bar, "reachable" | "reachableCost">;
  id?: string;
  onActive?: (index: number) => void;
  onPause?: (choice: PauseChoice) => void;
  onReachable?: (choice: ReachableChoice) => void;
}) {
  const item = (index: number, key: string, title: string, choose?: () => void) => (
    <li
      key={key}
      className={`flex h-6 cursor-default items-center rounded-[5px] px-2.5 ${index === active ? "bg-[var(--app-blue)] text-white" : ""}`}
      data-demo={key}
      id={id === undefined ? undefined : `${id}-item-${index}`}
      onClick={choose}
      onMouseMove={onActive === undefined ? undefined : () => onActive(index)}
      role="menuitem"
    >
      {title}
    </li>
  );
  return (
    <>
      {PAUSES.map((entry, index) => item(index, `pause-${entry.choice}`, entry.title, onPause && (() => onPause(entry.choice))))}
      {bar.reachable && (
        <>
          <li aria-hidden="true" className="mx-2.5 my-[5px] h-px bg-[var(--panel-line)]" role="separator" />
          {REACHABLES.map((entry, index) =>
            item(PAUSES.length + index, `reachable-${entry.choice}`, entry.title, onReachable && (() => onReachable(entry.choice))),
          )}
          {bar.reachableCost !== null && (
            <li aria-disabled="true" className={`flex h-6 items-center px-2.5 ${MUTED}`} role="menuitem">
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
    if (index < PAUSES.length) {
      onPause(PAUSES[index].choice);
    } else {
      onReachable(REACHABLES[index - PAUSES.length].choice);
    }
  }

  function onListKey(event: KeyboardEvent<HTMLUListElement>) {
    const moves: Record<string, number> = {
      ArrowDown: active === null ? 0 : Math.min(active + 1, count - 1),
      ArrowUp: active === null ? count - 1 : Math.max(active - 1, 0),
      Home: 0,
      End: count - 1,
    };
    if (event.key in moves) {
      event.preventDefault();
      setActive(moves[event.key]);
    } else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      if (active !== null) {
        choose(active);
      }
    } else if (event.key === "Escape") {
      event.preventDefault();
      close();
    } else if (event.key === "Tab") {
      setOpen(false);
    }
  }

  return (
    <div className="relative">
      <button
        ref={buttonRef}
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label="Pause or stay reachable"
        className={`flex size-7 items-center justify-center rounded-md ${MUTED}`}
        data-demo="timer"
        onClick={() => (open ? setOpen(false) : show(null))}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            show(event.key === "ArrowDown" ? 0 : count - 1);
          }
        }}
        type="button"
      >
        <TimerGlyph />
      </button>
      <AnimatePresence>
        {open && (
          <motion.ul
            key="menu"
            ref={listRef}
            animate={{ opacity: 1, scale: 1 }}
            aria-activedescendant={active === null ? undefined : `${id}-item-${active}`}
            aria-label="Pause or stay reachable"
            className="absolute -right-[52px] bottom-full z-10 mb-1 origin-bottom-right whitespace-nowrap rounded-[10px] border border-[var(--panel-line)] bg-[var(--panel)] p-[5px] shadow-[0_8px_24px_var(--shadow)] outline-none"
            exit={{ opacity: 0, scale: 0.97, transition: { duration: lessMotion ? 0 : duration.quick, ease: easing.smoothOut } }}
            initial={lessMotion ? false : { opacity: 0, scale: 0.97 }}
            onBlur={(event) => {
              const to = event.relatedTarget;
              if (!(to instanceof Node && event.currentTarget.parentElement?.contains(to))) {
                setOpen(false);
              }
            }}
            onKeyDown={onListKey}
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
function Timed({ end, label, name, onEnd }: { end: string; label: string; name: string; onEnd: () => void }) {
  return (
    <>
      <span className={`min-w-0 truncate tabular-nums ${MUTED}`}>{label}</span>
      <button className="flex h-7 shrink-0 items-center text-accent" data-demo={name} onClick={onEnd} type="button">
        {end}
      </button>
    </>
  );
}

/** The charge of the battery on one line below the headline: a small mark, the number, and what follows from it (`UI/Panel/BatteryLine.swift`). */
export function BatteryLine({ battery }: { battery: Battery }) {
  const quiet = "var(--panel-muted)";
  const red = "light-dark(#ff3b30, #ff453a)";
  const accent = battery.level === "normal" ? quiet : battery.level === "nearFloor" ? "var(--app-amber)" : red;
  const outline = battery.level === "stopped" ? red : quiet;
  const colors = "duration-[350ms] ease-smooth-out motion-reduce:transition-none";
  return (
    <div aria-label={battery.spoken} className={`flex items-center gap-[5px] whitespace-nowrap text-[12px] tabular-nums ${MUTED}`} role="img">
      {/* A body of 20 by 10 points with a 1 point outline, the level 1 point inside it, and a cap. */}
      <span aria-hidden="true" className="flex shrink-0 items-center gap-px">
        <span className={`flex h-2.5 w-5 rounded-[3px] border p-px transition-colors ${colors}`} style={{ borderColor: outline }}>
          <span className="flex-1 overflow-hidden rounded-[1px]">
            <span
              className={`block h-full transition-[width,background-color] ${colors}`}
              // A battery that is not empty always shows a sliver.
              style={{ width: battery.percent > 0 ? `max(1px, ${battery.percent}%)` : 0, background: accent }}
            />
          </span>
        </span>
        <span className={`h-1 w-[1.5px] rounded-r-[1px] transition-colors ${colors}`} style={{ background: outline }} />
      </span>
      {battery.charge !== null && (
        <>
          <span aria-hidden="true" className={`transition-colors ${colors}`} style={{ color: accent }}>
            <Flow>{battery.charge}</Flow>
          </span>
          <span aria-hidden="true" className="text-[color-mix(in_srgb,var(--panel-fg)_30%,transparent)]">
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

function Switch({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <button
      aria-checked={on}
      aria-label="agent caffeine"
      className={`flex h-5 w-11 shrink-0 items-center rounded-full p-0.5 transition-colors duration-fast ease-smooth-out motion-reduce:transition-none ${on ? "bg-[var(--app-blue)]" : "bg-[color-mix(in_srgb,var(--panel-fg)_20%,transparent)]"}`}
      data-demo="switch"
      onClick={() => onChange(!on)}
      role="switch"
      type="button"
    >
      <span
        className={`h-4 w-[26px] rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25)] transition-transform duration-fast ease-smooth-out motion-reduce:transition-none ${on ? "translate-x-[14px]" : "translate-x-0"}`}
      />
    </button>
  );
}

/** The one line below the headline that needs the reader. */
function AttentionLine({ attention, onHelper, onDismiss }: { attention: Attention; onHelper: () => void; onDismiss: () => void }) {
  const safety = attention.kind === "safetyStop";
  return (
    <div
      className={`flex flex-wrap items-center justify-center gap-x-2 gap-y-1 rounded-lg px-2.5 py-1.5 text-center text-[12px] leading-4 ${safety ? "bg-[color-mix(in_srgb,#ff9500_12%,transparent)]" : "bg-[color-mix(in_srgb,var(--panel-fg)_7%,transparent)]"}`}
    >
      <span className="flex items-start gap-1.5">
        <span aria-hidden="true" className="flex h-4 items-center">
          {safety ? (
            <svg className="size-3 text-[#ff9500]" fill="currentColor" viewBox="0 0 12 12">
              <path d="M5.13 1.5a1 1 0 0 1 1.74 0l4.5 8A1 1 0 0 1 10.5 11h-9a1 1 0 0 1-.87-1.5zM6 4.2a.6.6 0 0 0-.6.6v2.4a.6.6 0 0 0 1.2 0V4.8a.6.6 0 0 0-.6-.6zm0 4.4a.7.7 0 1 0 0 1.4.7.7 0 0 0 0-1.4z" fillRule="evenodd" />
            </svg>
          ) : (
            <svg className={`h-3 w-3.5 ${MUTED}`} fill="none" stroke="currentColor" strokeLinejoin="round" strokeWidth="1.1" viewBox="0 0 14 12">
              <rect height="7" rx="1" width="9" x="2.5" y="1.5" />
              <path d="M0.8 10.5h12.4" strokeLinecap="round" />
            </svg>
          )}
        </span>
        <span className="text-pretty">{attention.text}</span>
      </span>
      {!safety && (
        <span className="flex items-center gap-2.5">
          <button className="text-accent" data-demo="helper" onClick={onHelper} type="button">
            Set up…
          </button>
          {attention.kind === "lidClosedNotSetUp" && (
            <button aria-label="Dismiss" className={`flex size-4 items-center justify-center ${MUTED}`} onClick={onDismiss} type="button">
              <svg aria-hidden="true" className="size-2" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.5" viewBox="0 0 8 8">
                <path d="m1 1 6 6M7 1 1 7" />
              </svg>
            </button>
          )}
        </span>
      )}
    </div>
  );
}

function Fade({ children, id, lessMotion }: { children: ReactNode; id: string; lessMotion: boolean }) {
  return (
    <span className="grid">
      <AnimatePresence initial={false}>
        <motion.span
          key={id}
          animate={{ opacity: 1 }}
          className="[grid-area:1/1]"
          exit={{ opacity: 0 }}
          initial={lessMotion ? false : { opacity: 0 }}
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
  const [height, setHeight] = useState<number | "auto">("auto");

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
      className="overflow-hidden"
      initial={false}
      transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
    >
      <div ref={ref}>{children}</div>
    </motion.div>
  );
}

/** The window of the menu, for the simulator and for a still cut of it. */
export function PanelSurface({ children, className = "", label }: { children: ReactNode; className?: string; label: string }) {
  return (
    <div
      aria-label={label}
      className={`rounded-xl border border-[var(--panel-line)] bg-[var(--panel)] text-left text-[13px] leading-4 ${FG} ${className}`}
      role="group"
      style={{ fontFamily: SYSTEM_FONT }}
    >
      {children}
    </div>
  );
}

type AgentsPanelProps = {
  enabled: boolean;
  mode: Mode;
  view: View;
  /** Holds the loops while nobody sees the menu. */
  paused: boolean;
  onEnabled: (enabled: boolean) => void;
  onMode: (mode: Mode) => void;
  onHelper: () => void;
  onDismiss: () => void;
  onPause: (choice: PauseChoice) => void;
  onResume: () => void;
  onReachable: (choice: ReachableChoice) => void;
  onStopReachable: () => void;
};

export function AgentsPanel({
  enabled,
  mode,
  view,
  paused,
  onEnabled,
  onMode,
  onHelper,
  onDismiss,
  onPause,
  onResume,
  onReachable,
  onStopReachable,
}: AgentsPanelProps) {
  const lessMotion = useLessMotion();
  const move = { duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut };

  return (
    <PanelSurface
      className={`flex w-full flex-col shadow-[0_12px_32px_var(--shadow)] ${paused ? "panel-paused" : ""}`}
      label="The agent caffeine menu"
    >
      <div className="flex flex-col items-center px-4 pb-4 pt-3 text-center">
        <Robot paused={paused} pose={view.pose} />
        <p className="mt-2 text-[17px] leading-[22px]">
          <Fade id={view.title} lessMotion={lessMotion}>
            {view.title}
          </Fade>
        </p>
        <p className={`mt-0.5 text-pretty ${MUTED}`}>
          <Fade id={shape(view.subtitle)} lessMotion={lessMotion}>
            <Flow>{view.subtitle}</Flow>
          </Fade>
        </p>
        <div className="w-full">
          <AutoHeight lessMotion={lessMotion}>
            {view.battery !== null && (
              <div className="flex justify-center pt-1">
                <BatteryLine battery={view.battery} />
              </div>
            )}
            {view.attention !== null && (
              <div className="pt-3">
                <AttentionLine attention={view.attention} onDismiss={onDismiss} onHelper={onHelper} />
              </div>
            )}
          </AutoHeight>
        </div>
      </div>
      <div className="h-px bg-[var(--panel-line)]" />
      <AutoHeight lessMotion={lessMotion}>
        {view.emptyText !== null ? (
          <p className={`px-6 py-5 text-center text-[12px] text-pretty ${MUTED}`}>{view.emptyText}</p>
        ) : (
          <ul className="relative flex flex-col px-[13px] py-2">
            <AnimatePresence initial={false} mode="popLayout">
              {view.groups.map((group) => (
                <motion.li
                  key={group.agent}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  initial={lessMotion ? false : { opacity: 0 }}
                  layout={lessMotion ? false : "position"}
                  transition={move}
                >
                  <GroupRows group={group} />
                </motion.li>
              ))}
            </AnimatePresence>
          </ul>
        )}
      </AutoHeight>
      <div className="h-px bg-[var(--panel-line)]" />
      <div className="flex items-center gap-2 px-4 py-2">
        {view.bar.pausedLabel !== null ? (
          <Timed end="Resume" label={view.bar.pausedLabel} name="resume" onEnd={onResume} />
        ) : view.bar.reachableLabel !== null ? (
          <Timed end="Stop" label={view.bar.reachableLabel} name="stop" onEnd={onStopReachable} />
        ) : (
          <ModePicker mode={mode} onChange={onMode} />
        )}
        <span className="flex-1" />
        <Gear />
        {view.bar.timer && <TimerMenu bar={view.bar} onPause={onPause} onReachable={onReachable} />}
        <Switch on={enabled} onChange={onEnabled} />
      </div>
    </PanelSurface>
  );
}
