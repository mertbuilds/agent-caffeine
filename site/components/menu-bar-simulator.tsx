"use client";

import { useEffect, useRef, useState, type ReactNode, type RefObject, type SyntheticEvent } from "react";
import { AgentIcon } from "@/components/agent-icons";
import { AgentsPanel } from "@/components/agents-panel";
import { MenuIcon } from "@/components/menu-icon";
import {
  AGENTS,
  DEMO,
  INITIAL,
  PRESETS,
  advance,
  demo,
  graceLeft,
  iconLabel,
  preset,
  setWorking,
  start,
  stop,
  tickEvery,
  view,
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

function Playing({
  on,
  onToggle,
  ref,
}: {
  on: boolean;
  onToggle: () => void;
  ref: RefObject<HTMLDivElement | null>;
}) {
  return (
    <div ref={ref} className="flex items-center gap-2 text-sm text-muted">
      {on ? "Playing examples" : "Play examples"}
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
  const [sim, setSim] = useState<SimState>(INITIAL);
  const [chosen, setChosen] = useState<PresetId | null>(DEMO[0].preset);
  const [autoplay, setAutoplay] = useState(true);
  const [step, setStep] = useState(0);
  const demoing = autoplay && !lessMotion;
  const playing = demoing && seen && !hidden;
  const marked = demoing ? DEMO[step].preset : chosen;
  const shown = view(sim);
  const every = tickEvery(sim);

  useEffect(() => {
    if (!playing) {
      return;
    }
    const timer = window.setTimeout(() => {
      const next = (step + 1) % DEMO.length;
      setSim((state) => demo(state, DEMO[next]));
      setStep(next);
    }, DEMO[step].hold);
    return () => window.clearTimeout(timer);
  }, [playing, step]);

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
      setChosen(DEMO[step].idle === undefined ? DEMO[step].preset : null);
    }
  }

  function change(next: (state: SimState) => SimState) {
    setSim(next);
    setChosen(null);
  }

  return (
    <div
      ref={ref}
      className="grid w-full max-w-[36rem] gap-8 lg:max-w-none lg:grid-cols-[minmax(0,22rem)_minmax(0,36rem)] lg:justify-center lg:gap-16"
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
                on={demoing}
                ref={pauseRef}
                onToggle={() => {
                  if (demoing) {
                    stopDemo();
                    return;
                  }
                  setSim((state) => demo(state, DEMO[0]));
                  setStep(0);
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
                  onClick={() => change((state) => ({ ...state, power }))}
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
              className="flex h-[22px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-2"
              role="img"
            >
              <HeldIcon className="size-[18px]" held={shown.held} />
            </span>
            <span aria-hidden="true" className="w-14 text-center tabular-nums">
              9:41
            </span>
          </div>
          <div className="min-h-[18.75rem] w-[320px] max-w-full sm:mr-[3.875rem]">
            <AgentsPanel
              enabled={sim.enabled}
              mode={sim.mode}
              onEnabled={(enabled) => change((state) => ({ ...state, enabled }))}
              onMode={(mode) => change((state) => ({ ...state, mode }))}
              onOverride={() => change((state) => ({ ...state, overrideInstalled: true }))}
              view={shown}
            />
          </div>
        </div>
        <div aria-live="polite" className="flex min-h-24 items-start gap-3">
          <HeldIcon
            className={`mt-0.5 size-7 shrink-0 transition-colors duration-fast motion-reduce:transition-none ${shown.held ? "text-accent" : "text-muted"}`}
            held={shown.held}
          />
          <div className="flex min-w-0 flex-col gap-1">
            <p className={`text-xl font-medium leading-snug ${shown.held ? "text-fg" : "text-muted"}`}>
              {shown.outcome.title} <span className="font-normal text-muted">{shown.outcome.reason}</span>
            </p>
            {shown.outcome.hint !== "" && <p className="text-sm text-muted">{shown.outcome.hint}</p>}
          </div>
        </div>
      </div>
    </div>
  );
}
