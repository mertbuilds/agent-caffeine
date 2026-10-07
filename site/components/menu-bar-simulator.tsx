"use client";

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
import { easing } from "@/lib/motion";
import {
  AGENTS,
  BATTERY_LEVELS,
  DEMO,
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
const SEGMENT = "h-7 whitespace-nowrap rounded-full px-2.5 text-sm transition-colors duration-fast ease-smooth-out motion-reduce:transition-none";
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

type Fill = { key: string; ms: number } | "full" | null;

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
          <span className="relative">Demo playing</span>
        </span>
      ) : (
        <span className="text-muted">Demo stopped</span>
      )}
      <button
        aria-label={on ? "Stop the demo" : "Play the demo"}
        className="flex size-6 items-center justify-center rounded-full border border-border text-fg transition-colors duration-fast ease-smooth-out hover:border-fg motion-reduce:transition-none"
        onClick={onToggle}
        type="button"
      >
        <svg aria-hidden="true" className="size-2.5" fill="currentColor" viewBox="0 0 10 10">
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

const CHOICES: readonly { choice: Choice; title: string; spoken: string }[] = [
  { choice: "working", title: "Working", spoken: "working" },
  { choice: "waiting", title: "Waiting", spoken: "waiting for you" },
  { choice: "idle", title: "Idle", spoken: "idle" },
  // Not "Closed": that is the word of the lid.
  { choice: "closed", title: "Quit", spoken: "quit" },
];

function Setting({ children, label }: { children: ReactNode; label: string }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
      <span className="text-sm text-muted">{label}</span>
      <Segmented label={label}>{children}</Segmented>
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
  const [chosen, setChosen] = useState<PresetId | null>(DEMO[0].preset);
  const [autoplay, setAutoplay] = useState(true);
  const [cue, setCue] = useState<Cue>(DEMO_START);
  const [point, setPoint] = useState<Point | null>(null);
  const [ring, setRing] = useState<{ id: number; at: Point } | null>(null);
  const demoing = autoplay && !lessMotion;
  const playing = demoing && seen && !hidden;
  const marked = demoing ? DEMO[cue.step].preset : chosen;
  const caption = PRESETS.find((entry) => entry.id === marked)?.point ?? null;
  const shown = view(sim);
  const every = tickEvery(sim);
  const target = cueTarget(cue) ?? "tag";
  const waiting = cue.phase === "lead" || cue.phase === "hold";
  const fill: Fill = !waiting ? "full" : playing ? { key: `${cue.step}-${cue.phase}`, ms: cueTime(cue) } : null;
  const flips = useChanges(String(shown.held));
  const onBattery = sim.power === "battery";

  function press(name: string) {
    const root = ref.current;
    const element = root?.querySelector(`[data-demo="${name}"]`);
    if (root === null || !(element instanceof HTMLElement)) {
      return;
    }
    // On a narrow screen the situations are one row that scrolls: the one being pressed comes into it.
    const row = element.closest("[data-scroller]");
    if (row instanceof HTMLElement && row.scrollWidth > row.clientWidth) {
      row.scrollTo({ left: element.offsetLeft - (row.clientWidth - element.offsetWidth) / 2, behavior: "smooth" });
    }
    element.animate([{ transform: "scale(1)" }, { transform: "scale(0.94)" }, { transform: "scale(1)" }], {
      duration: 2 * DEMO_PRESS,
      easing: `cubic-bezier(${easing.smoothOut.join(",")})`,
    });
    const at = pointAt(root, name, !wide);
    if (at !== null && wide) {
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
        setSim((state) => preset(state, DEMO[after.step].preset));
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
      setChosen(DEMO[cue.step].preset);
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
      className="relative flex w-full max-w-[36rem] flex-col gap-8 lg:max-w-none lg:gap-10"
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
      <div className="flex flex-col gap-3 lg:items-center">
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
                setSim((state) => preset(state, DEMO[0].preset));
                setCue(DEMO_START);
                setAutoplay(true);
              }}
            />
          )}
        </div>
        <div
          className="-mx-4 flex gap-2 overflow-x-auto px-4 py-0.5 [scrollbar-width:none] sm:mx-0 sm:flex-wrap sm:overflow-visible sm:px-0 lg:justify-center [&::-webkit-scrollbar]:hidden"
          data-scroller
        >
          {PRESETS.map((entry) => (
            <button
              key={entry.id}
              aria-pressed={marked === entry.id}
              className={`${CHIP} shrink-0 whitespace-nowrap ${marked === entry.id ? CHIP_ON : CHIP_OFF}`}
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
        {/* The point of the chosen situation. The room stays when the reader sets things by hand, so nothing below moves. */}
        <p className="min-h-[3lh] max-w-[36rem] text-pretty text-sm leading-normal text-muted sm:min-h-[2lh] lg:text-center">{caption}</p>
      </div>
      <div className="grid gap-8 lg:grid-cols-[minmax(0,24rem)_minmax(0,36rem)] lg:justify-center lg:gap-16">
        <div className="flex min-w-0 flex-col gap-6">
          <div className="flex flex-col gap-3">
            <h3 className="text-sm text-muted">Or set it yourself</h3>
            <ul className="flex flex-col divide-y divide-border border-y border-border">
              {AGENTS.map((agent) => {
                const now = choiceOf(sim, agent.id);
                return (
                  <li key={agent.id} className="flex flex-col items-start gap-2 py-3">
                    <span className="flex min-w-0 items-center gap-2">
                      <AgentIcon className="size-5 shrink-0" name={agent.icon} />
                      <span className="truncate">{agent.name}</span>
                    </span>
                    <Segmented label={`What ${agent.name} does`}>
                      {CHOICES.map((entry) => (
                        <button
                          key={entry.choice}
                          aria-label={`Set ${agent.name} to ${entry.spoken}`}
                          aria-pressed={now === entry.choice}
                          className={`${SEGMENT} ${now === entry.choice ? SEGMENT_ON : SEGMENT_OFF}`}
                          data-demo={`${entry.choice}-${agent.id}`}
                          onClick={() => change((state) => setChoice(state, agent.id, entry.choice))}
                          type="button"
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
          <div className="flex flex-col gap-3">
            <Setting label="Power">
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
            </Setting>
            <Setting label="Lid">
              {(["open", "closed"] as const).map((lid) => (
                <button
                  key={lid}
                  aria-pressed={sim.lid === lid}
                  className={`${SEGMENT} ${sim.lid === lid ? SEGMENT_ON : SEGMENT_OFF}`}
                  data-demo={`lid-${lid}`}
                  onClick={() => change((state) => setLid(state, lid))}
                  type="button"
                >
                  {lid === "open" ? "Open" : "Closed"}
                </button>
              ))}
            </Setting>
            <div className={`transition-opacity duration-fast motion-reduce:transition-none ${onBattery ? "" : "opacity-40"}`}>
              <Setting label="Battery level">
                {BATTERY_LEVELS.map((level) => (
                  <button
                    key={level}
                    aria-pressed={onBattery && sim.battery === level}
                    className={`${SEGMENT} tabular-nums ${onBattery && sim.battery === level ? SEGMENT_ON : SEGMENT_OFF}`}
                    data-demo={`battery-${level}`}
                    disabled={!onBattery}
                    onClick={() => change((state) => setBattery(state, level))}
                    type="button"
                  >
                    {level}%
                  </button>
                ))}
              </Setting>
            </div>
          </div>
          <p className="text-pretty text-sm leading-normal text-muted">
            Time runs faster here. In the app an agent that waits for you keeps your Mac awake for 5 minutes, and you can change that time
          </p>
        </div>
        <div className="order-first flex w-full min-w-0 flex-col items-end gap-1 self-start rounded-xl border border-border p-1 pb-6 lg:order-none">
          <div className="flex h-6 w-full items-center justify-end rounded-md bg-[color-mix(in_srgb,var(--surface)_85%,transparent)] px-1.5 text-[13px] text-fg backdrop-blur">
            {GLYPHS.map((width, index) => (
              <span key={index} aria-hidden="true" className="flex h-[22px] items-center px-2">
                <span className="h-3.5 rounded-[3px] bg-current opacity-30" style={{ width }} />
              </span>
            ))}
            <span
              aria-label={shown.iconLabel}
              className="relative flex h-[22px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-2"
              role="img"
            >
              {flips > 0 && (
                <span key={flips} aria-hidden="true" className="demo-pulse absolute inset-0 rounded-[5px] bg-accent opacity-0" />
              )}
              <MenuIcon className="relative h-5 w-[21px]" look={shown.look} />
            </span>
            <span aria-hidden="true" className="w-14 text-center tabular-nums">
              {shown.clock}
            </span>
          </div>
          <div className="min-h-[25.5rem] w-full sm:mr-[3.875rem] sm:w-[320px]">
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
          <p aria-atomic="true" aria-live={demoing ? "off" : "polite"} className="sr-only">
            {shown.title}. {shown.subtitle}
          </p>
        </div>
      </div>
      {demoing && wide && ring !== null && (
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
