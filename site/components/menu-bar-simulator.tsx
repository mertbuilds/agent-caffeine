"use client";

import { AnimatePresence, motion } from "motion/react";
import {
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactNode,
  type RefObject,
  type SyntheticEvent,
} from "react";
import { AgentIcon } from "@/components/agent-icons";
import { AgentsPanel } from "@/components/agents-panel";
import { MenuIcon } from "@/components/menu-icon";
import { duration, easing } from "@/lib/motion";
import {
  AGENTS,
  DEMO,
  DEMO_MOVE,
  DEMO_PRESS,
  DEMO_START,
  INITIAL,
  PRESETS,
  advance,
  cueTarget,
  cueTime,
  demo,
  graceLeft,
  iconLabel,
  installOverride,
  nextCue,
  preset,
  setEnabled,
  setMode,
  setPower,
  setWorking,
  start,
  stop,
  tickEvery,
  upcoming,
  view,
  type Cue,
  type DemoAction,
  type PresetId,
  type SimState,
} from "@/lib/simulator";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

/** Stand-ins for the other status items, as wide as each glyph, in pixels. */
const GLYPHS = [16, 14, 20];

const CHIP =
  "rounded-full border px-3 py-1.5 text-sm leading-tight transition-colors duration-fast ease-smooth-out motion-reduce:transition-none";
const CHIP_ON = "border-fg bg-fg text-bg";
const CHIP_OFF = "border-border text-fg hover:border-fg";
const SEGMENT = "h-7 rounded-full px-2.5 text-sm transition-colors duration-fast ease-smooth-out motion-reduce:transition-none";
const SEGMENT_ON = "bg-bg text-fg shadow-[0_1px_2px_var(--shadow)]";
const SEGMENT_OFF = "text-muted hover:text-fg";

/** Two columns, where the controls and the panel are in sight together and the demo pointer can travel between them. */
const WIDE = "(min-width: 1024px)";

function subscribeWide(onChange: () => void): () => void {
  const query = window.matchMedia(WIDE);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
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
    return { x: box.left - origin.left + box.width / 2, y: box.top - origin.top + box.height / 2 };
  }
  return { x: box.right - origin.left - Math.min(10, box.width / 3), y: box.bottom - origin.top - 4 };
}

function presetOf(action: DemoAction): PresetId | null {
  return action.use === "preset" ? action.id : null;
}

/** Both icon states stacked, so a change crossfades. */
function HeldIcon({ className, held }: { className: string; held: boolean }) {
  return (
    <span className={`grid ${className}`}>
      {[true, false].map((state) => (
        <MenuIcon
          key={String(state)}
          className={`size-full transition-opacity duration-fast ease-smooth-out [grid-area:1/1] motion-reduce:transition-none ${held === state ? "opacity-100" : "opacity-0"}`}
          held={state}
        />
      ))}
    </span>
  );
}

type Fill = { key: string; ms: number } | "full" | null;

/** The demo's status: a tag with a live dot that fills up to the next step, and the pause and play button. */
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
    <div ref={ref} className="flex items-center gap-2 text-sm">
      {on ? (
        <span
          className="relative flex h-6 items-center gap-1.5 overflow-hidden rounded-full border border-border pl-2 pr-2.5 text-fg"
          data-demo="tag"
        >
          {fill !== null && (
            <span
              key={fill === "full" ? "full" : fill.key}
              aria-hidden="true"
              className={`absolute inset-0 origin-left bg-[color-mix(in_srgb,var(--accent)_16%,transparent)] ${fill === "full" ? "" : "demo-fill"}`}
              style={fill === "full" ? undefined : { animationDuration: `${fill.ms}ms` }}
            />
          )}
          <span aria-hidden="true" className={`relative size-1.5 rounded-full bg-accent ${live ? "demo-live" : ""}`} />
          <span className="relative">Demo</span>
        </span>
      ) : (
        <span className="text-muted">Paused</span>
      )}
      <button
        aria-label={on ? "Pause the examples" : "Play the examples"}
        className="flex size-6 items-center justify-center rounded-full border border-border text-fg transition-colors duration-fast ease-smooth-out hover:border-fg motion-reduce:transition-none"
        onClick={onToggle}
        type="button"
      >
        <svg aria-hidden="true" className="size-2.5" fill="currentColor" viewBox="0 0 10 10">
          {on ? (
            <>
              <rect height="8" rx="0.75" width="3" x="1.5" y="1" />
              <rect height="8" rx="0.75" width="3" x="5.5" y="1" />
            </>
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
      className="demo-in pointer-events-none absolute left-0 top-0 z-20"
      style={{
        transform: `translate(${at.x - 2}px, ${at.y - 2}px)`,
        transition: `transform ${DEMO_MOVE}ms var(--ease-smooth-out)`,
      }}
    >
      <svg
        className={`block h-[23px] w-[17px] drop-shadow-[0_1px_1px_var(--shadow)] transition-transform duration-quick ease-smooth-out ${pressing ? "scale-[0.85]" : ""}`}
        style={{ transformOrigin: "2px 2px" }}
        viewBox="0 0 14 19"
      >
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
    <div aria-label={label} className="flex shrink-0 rounded-full bg-surface p-0.5" role="group">
      {children}
    </div>
  );
}

function Grace({ left }: { left: number }) {
  return (
    <div className="flex min-w-0 items-center gap-2 text-sm text-muted">
      <span className="h-1 w-6 shrink-0 sm:w-8 overflow-hidden rounded-full bg-surface">
        <span
          className="block h-full origin-left rounded-full bg-accent transition-transform duration-[250ms] ease-linear motion-reduce:transition-none"
          style={{ transform: `scaleX(${left})` }}
        />
      </span>
      <span className="truncate">
        <span className="hidden sm:inline">Still counts</span>
        <span className="sm:hidden">Counts</span> as working
      </span>
    </div>
  );
}

export function MenuBarSimulator() {
  const ref = useRef<HTMLDivElement>(null);
  const pauseRef = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.2);
  const hidden = useTabHidden();
  const lessMotion = useLessMotion();
  const wide = useWide();
  const [sim, setSim] = useState<SimState>(INITIAL);
  const [chosen, setChosen] = useState<PresetId | null>(presetOf(DEMO[0].action));
  const [autoplay, setAutoplay] = useState(true);
  const [cue, setCue] = useState<Cue>(DEMO_START);
  const [point, setPoint] = useState<Point | null>(null);
  const [ring, setRing] = useState<{ id: number; at: Point } | null>(null);
  const demoing = autoplay && !lessMotion;
  const playing = demoing && seen && !hidden;
  const marked = demoing ? presetOf(DEMO[cue.step].action) : chosen;
  const shown = view(sim);
  const every = tickEvery(sim);
  const target = cueTarget(cue) ?? "tag";
  const next = upcoming(cue);
  // The demo opens the mode picker with its first press and highlights the mode with its second.
  const menu = demoing && next.use === "mode" && cue.target > 0 ? (cue.phase === "press" ? next.mode : sim.mode) : null;
  const waiting = cue.phase === "lead" || cue.phase === "hold";
  const fill: Fill = !waiting ? "full" : playing ? { key: `${cue.step}-${cue.phase}`, ms: cueTime(cue) } : null;
  const outcomeKey = `${shown.outcome.title} ${shown.outcome.reason} ${shown.outcome.hint}`;
  const swaps = useChanges(outcomeKey);
  const flips = useChanges(String(shown.held));

  function press(name: string) {
    const root = ref.current;
    const element = root?.querySelector(`[data-demo="${name}"]`);
    if (root === null || !(element instanceof HTMLElement)) {
      return;
    }
    element.animate([{ transform: "scale(1)" }, { transform: "scale(0.94)" }, { transform: "scale(1)" }], {
      duration: 2 * DEMO_PRESS,
      easing: `cubic-bezier(${easing.smoothOut.join(",")})`,
    });
    const at = pointAt(root, name, !wide);
    if (at !== null) {
      setRing((last) => ({ id: (last?.id ?? 0) + 1, at }));
    }
  }

  useEffect(() => {
    if (!playing) {
      return;
    }
    const timer = window.setTimeout(() => {
      const after = nextCue(cue);
      if (cue.phase === "move") {
        press(target);
      }
      if (after.phase === "hold") {
        setSim((state) => demo(state, DEMO[after.step].action));
      }
      setCue(after);
    }, cueTime(cue));
    return () => window.clearTimeout(timer);
  }, [playing, cue]);

  useEffect(() => {
    const root = ref.current;
    if (!demoing || root === null) {
      return;
    }
    // A control that is gone, like a closed menu's option, leaves the pointer where it was.
    const place = () => setPoint((last) => pointAt(root, target) ?? last);
    place();
    window.addEventListener("resize", place);
    return () => window.removeEventListener("resize", place);
  }, [demoing, target]);

  useEffect(() => {
    if (every === null || !seen || hidden) {
      return;
    }
    const timer = window.setInterval(() => setSim((state) => advance(state, every)), every);
    return () => window.clearInterval(timer);
  }, [every, seen, hidden]);

  function fromPause(event: SyntheticEvent) {
    return event.target instanceof Node && pauseRef.current?.contains(event.target) === true;
  }

  function stopDemo() {
    if (demoing) {
      setAutoplay(false);
      setChosen(presetOf(DEMO[cue.step].action));
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
      ref={ref}
      className="relative grid w-full max-w-[36rem] gap-8 lg:max-w-none lg:grid-cols-[minmax(0,22rem)_minmax(0,36rem)] lg:justify-center lg:gap-16"
      onClickCapture={(event) => {
        if (!fromPause(event)) {
          stopDemo();
        }
      }}
      onKeyDown={(event) => {
        // Enter and Space reach the demo as a click.
        if (!fromPause(event) && event.key !== "Enter" && event.key !== " ") {
          stopDemo();
        }
      }}
    >
      <div className="flex min-w-0 flex-col gap-8">
        <div className="flex flex-col gap-3">
          <div className="flex min-h-6 items-center justify-between gap-4">
            <h3 className="text-sm text-muted">Try a situation</h3>
            {!lessMotion && (
              <Playing
                fill={fill}
                live={playing}
                on={demoing}
                ref={pauseRef}
                onToggle={() => {
                  if (demoing) {
                    stopDemo();
                    return;
                  }
                  setSim((state) => demo(state, DEMO[0].action));
                  setCue(DEMO_START);
                  setAutoplay(true);
                }}
              />
            )}
          </div>
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((entry) => (
              <button
                key={entry.id}
                aria-pressed={marked === entry.id}
                className={`${CHIP} ${marked === entry.id ? CHIP_ON : CHIP_OFF}`}
                data-demo={`preset-${entry.id}`}
                onClick={() => {
                  setSim((state) => preset(state, entry.id));
                  setChosen(entry.id);
                }}
                type="button"
              >
                {entry.title}
              </button>
            ))}
          </div>
        </div>
        <div className="flex flex-col gap-3">
          <h3 className="text-sm text-muted">Or run the agents yourself</h3>
          <ul className="flex flex-col divide-y divide-border border-y border-border">
            {AGENTS.map((agent) => {
              const run = sim.runs.find((candidate) => candidate.id === agent.id);
              const left = run === undefined ? null : graceLeft(run, sim.now);
              return (
                <li key={agent.id} className="flex flex-col gap-1.5 py-3">
                  <div className="flex items-center gap-3">
                    <span className="flex min-w-0 flex-1 items-center gap-2">
                      <AgentIcon className="size-5 shrink-0" name={agent.icon} />
                      <span className="truncate">{agent.name}</span>
                    </span>
                    <button
                      aria-label={`${run === undefined ? "Start" : "Stop"} ${agent.name}`}
                      className={`h-7 w-14 shrink-0 rounded-full border text-sm transition-colors duration-fast ease-smooth-out motion-reduce:transition-none ${run === undefined ? "border-fg" : "border-border text-muted hover:border-fg hover:text-fg"}`}
                      data-demo={`run-${agent.id}`}
                      onClick={() => change((state) => (run === undefined ? start(state, agent.id) : stop(state, agent.id)))}
                      type="button"
                    >
                      {run === undefined ? "Start" : "Stop"}
                    </button>
                  </div>
                  <div className="flex h-7 items-center gap-3 sm:pl-7">
                    {run === undefined ? (
                      <p className="text-sm text-muted">Not running</p>
                    ) : (
                      <>
                        <Segmented label={`What ${agent.name} does`}>
                          {[true, false].map((working) => (
                            <button
                              key={String(working)}
                              aria-label={`Set ${agent.name} to ${working ? "working" : "idle"}`}
                              aria-pressed={run.working === working}
                              className={`${SEGMENT} ${run.working === working ? SEGMENT_ON : SEGMENT_OFF}`}
                              data-demo={`${working ? "working" : "idle"}-${agent.id}`}
                              onClick={() => change((state) => setWorking(state, agent.id, working))}
                              type="button"
                            >
                              {working ? "Working" : "Idle"}
                            </button>
                          ))}
                        </Segmented>
                        {left !== null &&
                          (left > 0 ? (
                            <Grace left={left} />
                          ) : (
                            <p className="min-w-0 truncate text-sm text-muted">Waiting at its prompt</p>
                          ))}
                      </>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <span className="text-sm text-muted">Power</span>
            <Segmented label="Power">
              {(["adapter", "battery"] as const).map((power) => (
                <button
                  key={power}
                  aria-pressed={sim.power === power}
                  className={`${SEGMENT} ${sim.power === power ? SEGMENT_ON : SEGMENT_OFF}`}
                  data-demo={`power-${power}`}
                  onClick={() => change((state) => setPower(state, power))}
                  type="button"
                >
                  {power === "adapter" ? "Power adapter" : "Battery"}
                </button>
              ))}
            </Segmented>
          </div>
        </div>
        <p className="text-pretty text-sm leading-normal text-muted">
          Time runs faster here. In the app an idle agent stops holding the Mac after 2 minutes
        </p>
      </div>
      <div className="order-first flex min-w-0 flex-col gap-6 lg:order-none lg:gap-8">
        <div className="flex w-full flex-col items-end gap-1 rounded-xl border border-border p-1 pb-6">
          <div className="flex h-6 w-full items-center justify-end rounded-md bg-[color-mix(in_srgb,var(--surface)_85%,transparent)] px-1.5 text-[13px] text-fg backdrop-blur">
            {GLYPHS.map((width, index) => (
              <span key={index} aria-hidden="true" className="flex h-[22px] items-center px-2">
                <span className="h-3.5 rounded-[3px] bg-current opacity-30" style={{ width }} />
              </span>
            ))}
            <span
              aria-label={iconLabel(shown.held)}
              className="relative flex h-[22px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-2"
              role="img"
            >
              {flips > 0 && (
                <span key={flips} aria-hidden="true" className="demo-pulse absolute inset-0 rounded-[5px] bg-accent opacity-0" />
              )}
              <HeldIcon className="relative size-[18px]" held={shown.held} />
            </span>
            <span aria-hidden="true" className="w-14 text-center tabular-nums">
              9:41
            </span>
          </div>
          <div className="min-h-[18.75rem] w-[320px] max-w-full sm:mr-[3.875rem]">
            <AgentsPanel
              enabled={sim.enabled}
              menu={menu}
              mode={sim.mode}
              onEnabled={(enabled) => change((state) => setEnabled(state, enabled))}
              onMode={(mode) => change((state) => setMode(state, mode))}
              onOverride={() => change(installOverride)}
              view={shown}
            />
          </div>
        </div>
        <div aria-live={demoing ? "off" : "polite"} className="flex min-h-24 items-start gap-3">
          <HeldIcon
            className={`mt-0.5 size-7 shrink-0 transition-colors duration-fast motion-reduce:transition-none ${shown.held ? "text-accent" : "text-muted"}`}
            held={shown.held}
          />
          <div className="relative grid min-w-0 flex-1 overflow-hidden">
            <AnimatePresence initial={false}>
              <motion.div
                key={outcomeKey}
                animate={{ opacity: 1, y: 0 }}
                className="flex flex-col gap-1 [grid-area:1/1]"
                exit={{ opacity: 0, y: -6 }}
                initial={lessMotion ? false : { opacity: 0, y: 6 }}
                transition={{ duration: lessMotion ? 0 : duration.fast, ease: easing.smoothOut }}
              >
                <p className={`text-xl font-medium leading-snug ${shown.held ? "text-fg" : "text-muted"}`}>
                  {shown.outcome.title} <span className="font-normal text-muted">{shown.outcome.reason}</span>
                </p>
                {shown.outcome.hint !== "" && <p className="text-sm text-muted">{shown.outcome.hint}</p>}
              </motion.div>
            </AnimatePresence>
            {swaps > 0 && (
              <span
                key={swaps}
                aria-hidden="true"
                className="demo-sweep pointer-events-none absolute inset-0 bg-[linear-gradient(90deg,transparent,color-mix(in_srgb,var(--accent)_16%,transparent),transparent)] opacity-0"
              />
            )}
          </div>
        </div>
      </div>
      {demoing && ring !== null && (
        <span
          key={ring.id}
          aria-hidden="true"
          className="pointer-events-none absolute left-0 top-0 z-20"
          style={{ transform: `translate(${ring.at.x}px, ${ring.at.y}px)` }}
        >
          <span className="demo-ring absolute -left-5 -top-5 size-10 rounded-full border-2 border-accent bg-[color-mix(in_srgb,var(--accent)_20%,transparent)] opacity-0" />
        </span>
      )}
      {demoing && wide && point !== null && <Pointer at={point} pressing={cue.phase === "press"} />}
    </div>
  );
}
