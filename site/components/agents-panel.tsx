"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { duration, easing } from "@/lib/motion";
import { MODES, type Mode, type View } from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";

const TERTIARY = "text-[color-mix(in_srgb,var(--muted)_70%,transparent)]";
const DOTS = { active: "#34c759", waitingForInput: "#ffcc00" } as const;

/** Places the menu so the selected row and its text sit over the button's, as macOS does. */
const ROW = 20;
const MENU_TOP = -5;
const MENU_LEFT = -14;

function Chevrons() {
  return (
    <span className="flex h-3.5 w-3.5 items-center justify-center rounded-[4px] bg-accent text-white">
      <svg
        className="h-2 w-1.5"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.2"
        viewBox="0 0 6 8"
      >
        <path d="M1 3 3 1l2 2M1 5l2 2 2-2" />
      </svg>
    </span>
  );
}

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
    <div className="flex flex-col gap-1">
      <span className="sr-only" id={`${id}-label`}>
        Mode
      </span>
      <div className="relative self-start">
        <button
          ref={buttonRef}
          aria-describedby={`${id}-explanation`}
          aria-expanded={open}
          aria-haspopup="listbox"
          aria-labelledby={`${id}-label ${id}-button`}
          className="flex h-[18px] items-center gap-1.5 rounded-[5px] border border-border bg-bg pl-2 pr-px text-[11px] leading-[13px] shadow-[0_1px_1px_var(--shadow)]"
          id={`${id}-button`}
          onClick={() => (open ? setOpen(false) : show())}
          onKeyDown={onButtonKey}
          type="button"
        >
          {MODES[selected].title}
          <Chevrons />
        </button>
        <AnimatePresence>
          {open && (
            <motion.ul
              key="menu"
              ref={listRef}
              animate={{ opacity: 1, scale: 1 }}
              aria-activedescendant={`${id}-option-${active}`}
              aria-labelledby={`${id}-label`}
              className="absolute z-10 whitespace-nowrap rounded-[6px] border border-border bg-bg p-1 text-[12px] leading-[15px] shadow-[0_8px_24px_var(--shadow)] outline-none"
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
              style={{
                left: MENU_LEFT,
                top: MENU_TOP - selected * ROW,
                transformOrigin: `0 ${4 + selected * ROW + ROW / 2}px`,
              }}
              tabIndex={-1}
              transition={{ duration: duration.fast, ease: easing.smoothOut }}
            >
              {MODES.map((entry, index) => (
                <li
                  key={entry.mode}
                  aria-selected={index === selected}
                  className={`flex h-5 cursor-default items-center rounded-[2px] pl-1 pr-3 ${index === active ? "bg-accent text-white" : ""}`}
                  id={`${id}-option-${index}`}
                  onClick={() => choose(index)}
                  onMouseMove={() => setActive(index)}
                  role="option"
                >
                  <span aria-hidden="true" className="flex w-3.5 shrink-0">
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
      <p className="truncate text-[11px] leading-[13px] text-muted" id={`${id}-explanation`}>
        {MODES[selected].explanation}
      </p>
    </div>
  );
}

function Switch({ on, onChange }: { on: boolean; onChange: (on: boolean) => void }) {
  return (
    <button
      aria-checked={on}
      aria-label="agent caffeine"
      className={`flex h-4 w-[26px] shrink-0 items-center rounded-full p-px transition-colors duration-fast ease-smooth-out motion-reduce:transition-none ${on ? "bg-accent" : "bg-[color-mix(in_srgb,var(--fg)_18%,transparent)]"}`}
      onClick={() => onChange(!on)}
      role="switch"
      type="button"
    >
      <span
        className={`size-3.5 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25)] transition-transform duration-fast ease-smooth-out motion-reduce:transition-none ${on ? "translate-x-2.5" : "translate-x-0"}`}
      />
    </button>
  );
}

function BatteryGlyph({ level }: { level: number }) {
  return (
    <svg aria-hidden="true" className="h-2.5 w-[18px] shrink-0" fill="none" viewBox="0 0 18 10">
      <rect height="9" rx="2.2" stroke="currentColor" width="14.5" x="0.5" y="0.5" />
      <rect fill="currentColor" height="6" rx="1" width={11.5 * level} x="2" y="2" />
      <path d="M16.5 3.5v3" stroke="currentColor" strokeLinecap="round" strokeWidth="1.2" />
    </svg>
  );
}

function BatteryRow({ battery, onOverride }: { battery: View["battery"]; onOverride: () => void }) {
  if (battery === "overrideActive") {
    return (
      <p className="flex items-center gap-1.5 text-[11px] leading-[13px] text-[#248a3d] dark:text-[#30d158]">
        <BatteryGlyph level={1} />
        On battery: override active
      </p>
    );
  }
  if (battery === "lidWillSleep") {
    return (
      <div className="flex items-start gap-1.5 text-[11px] leading-[13px]">
        <p className="flex min-w-0 flex-1 items-start gap-1.5 text-[#b25f00] dark:text-[#ff9f0a]">
          <span className="flex h-[13px] items-center">
            <BatteryGlyph level={0.5} />
          </span>
          On battery: closing the lid will sleep this Mac
        </p>
        <button className="shrink-0 text-accent" onClick={onOverride} type="button">
          Turn on override…
        </button>
      </div>
    );
  }
  return null;
}

function Fade({ children, id, lessMotion }: { children: string; id: string; lessMotion: boolean }) {
  return (
    <span className="grid">
      <AnimatePresence initial={false}>
        <motion.span
          key={id}
          animate={{ opacity: 1 }}
          className="[grid-area:1/1]"
          exit={{ opacity: 0 }}
          initial={lessMotion ? false : { opacity: 0 }}
          transition={{ duration: lessMotion ? 0 : duration.quick, ease: easing.smoothOut }}
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

type AgentsPanelProps = {
  enabled: boolean;
  mode: Mode;
  view: View;
  onEnabled: (enabled: boolean) => void;
  onMode: (mode: Mode) => void;
  onOverride: () => void;
};

export function AgentsPanel({ enabled, mode, view, onEnabled, onMode, onOverride }: AgentsPanelProps) {
  const lessMotion = useLessMotion();
  const move = { duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut };

  return (
    <div
      aria-label="The agent caffeine menu bar panel"
      className="flex w-full flex-col gap-3 rounded-[10px] border border-border bg-bg p-3 text-left shadow-[0_8px_24px_var(--shadow)]"
      role="group"
    >
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-4">
          <span className="text-[13px] font-medium leading-4">agent caffeine</span>
          <Switch on={enabled} onChange={onEnabled} />
        </div>
        <p className="text-[12px] leading-[15px] text-muted">
          <Fade id={view.status} lessMotion={lessMotion}>
            {view.status}
          </Fade>
        </p>
        <ModePicker mode={mode} onChange={onMode} />
        <AutoHeight lessMotion={lessMotion}>
          <BatteryRow battery={view.battery} onOverride={onOverride} />
        </AutoHeight>
      </div>
      <div className="h-px bg-border" />
      <AutoHeight lessMotion={lessMotion}>
        <ul className="relative flex flex-col">
          <AnimatePresence initial={false} mode="popLayout">
            {view.rows.length === 0 ? (
              <motion.li
                key="empty"
                animate={{ opacity: 1 }}
                className={`text-[12px] leading-[15px] ${TERTIARY}`}
                exit={{ opacity: 0 }}
                initial={lessMotion ? false : { opacity: 0 }}
                transition={move}
              >
                No agents running
              </motion.li>
            ) : (
              view.rows.map((row) => (
                <motion.li
                  key={row.key}
                  animate={{ opacity: 1, y: 0 }}
                  className="flex items-center gap-2 py-0.5"
                  exit={{ opacity: 0, y: 4 }}
                  initial={lessMotion ? false : { opacity: 0, y: 4 }}
                  layout={lessMotion ? false : "position"}
                  transition={move}
                >
                  <span
                    aria-hidden="true"
                    className="size-2 shrink-0 rounded-full transition-colors duration-fast motion-reduce:transition-none"
                    style={{ background: DOTS[row.state] }}
                  />
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate text-[12px] leading-[15px]">{row.label}</span>
                    <span className="truncate text-[10px] leading-[13px] text-muted">{row.sub}</span>
                  </span>
                  <span className={`shrink-0 text-[10px] tabular-nums ${TERTIARY}`}>{row.time}</span>
                </motion.li>
              ))
            )}
          </AnimatePresence>
        </ul>
      </AutoHeight>
      <div className="h-px bg-border" />
      <div aria-hidden="true" className="flex gap-2 text-[12px] leading-[15px]">
        <span>Preferences…</span>
        <span className="ml-auto">Quit</span>
      </div>
    </div>
  );
}
