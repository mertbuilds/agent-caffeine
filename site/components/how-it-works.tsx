"use client";

import { useRef, type CSSProperties } from "react";
import { AgentIcon, type AgentIconName } from "@/components/agent-icons";
import { Cup } from "@/components/cup";
import { SectionHeading } from "@/components/section-heading";
import { drawing } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

/** Where on the track, from 0 to 1, the first agent starts working, both work, and the last goes idle. */
const MOMENTS = [1 / 6, 1 / 2, 5 / 6] as const;
const CAPTIONS = [
  "An agent starts working",
  "The Mac stays awake, lid open or closed",
  "The last agent goes idle, the Mac sleeps",
];
const RUNS: readonly { name: string; icon: AgentIconName; from: number; to: number }[] = [
  { name: "Claude Code", icon: "claudecode", from: MOMENTS[0], to: 0.6 },
  { name: "Codex", icon: "codex", from: 0.38, to: MOMENTS[2] },
];
const AWAKE = { from: MOMENTS[0], to: MOMENTS[2] };
/** How long, as a share of the track, a change takes to settle. */
const SETTLE = 0.04;
const linear = (share: number) => share;

/** A span on the track from `from`, as wide as the time between `from` and `to`. */
function span(from: number, to: number): CSSProperties {
  return { left: `${from * 100}%`, width: `max(2rem, ${Math.max(0, to - from) * 100}%)` };
}

export function HowItWorks() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref);
  const hidden = useTabHidden();
  const now = useLoop(seen && !hidden, drawing.timeline, drawing.timelineRest);
  const awake =
    stretch(now, AWAKE.from, AWAKE.from + SETTLE) * (1 - stretch(now, AWAKE.to, AWAKE.to + SETTLE));
  const asleep = stretch(now, AWAKE.to + SETTLE / 2, AWAKE.to + SETTLE * 2);

  return (
    <section className="mx-auto flex w-full max-w-[1120px] flex-col gap-12">
      <SectionHeading lead="Nothing to switch on. It follows your agents" title="How it works" />
      <div
        ref={ref}
        aria-label="A timeline: while Claude Code and then Codex work, the Mac is held awake. When the last one goes idle, the Mac sleeps"
        className="mx-auto flex w-full max-w-[760px] flex-col gap-8"
        role="img"
      >
        <div className="flex gap-3 sm:gap-4">
          <div className="flex w-8 shrink-0 flex-col gap-2">
            <div className="h-8" />
            <div className="h-8" />
            <div className="flex h-8 items-center justify-center">
              <Cup
                className={`size-7 transition-colors duration-slow ${awake > 0.5 ? "text-accent" : "text-fg"}`}
                full={awake}
              />
            </div>
          </div>
          <div className="relative flex min-w-0 flex-1 flex-col gap-2">
            {RUNS.map((run) => (
              <div key={run.name} className="relative h-8">
                <div
                  className={`absolute inset-y-0 flex items-center gap-1.5 overflow-hidden whitespace-nowrap rounded-full border bg-bg pl-1.5 pr-3 text-sm transition-colors duration-slow ${now > run.to ? "border-border text-muted" : "border-fg"}`}
                  style={{
                    ...span(run.from, Math.min(now, run.to)),
                    opacity: stretch(now, run.from, run.from + SETTLE / 2),
                  }}
                >
                  <AgentIcon className="size-5 shrink-0" name={run.icon} />
                  {run.name}
                </div>
              </div>
            ))}
            <div className="relative h-8">
              <div
                className="absolute inset-y-0 flex items-center overflow-hidden whitespace-nowrap rounded-full bg-accent px-3 text-sm text-bg"
                style={{
                  ...span(AWAKE.from, Math.min(now, AWAKE.to)),
                  opacity: stretch(now, AWAKE.from, AWAKE.from + SETTLE / 2),
                }}
              >
                Mac held awake
              </div>
              <div
                className="absolute inset-y-0 flex items-center gap-1.5 whitespace-nowrap pl-2 text-sm text-muted"
                style={{
                  left: `${AWAKE.to * 100}%`,
                  opacity: asleep,
                  transform: `translateY(${4 * (1 - asleep)}px)`,
                }}
              >
                <svg
                  aria-hidden="true"
                  className="size-4 shrink-0"
                  fill="none"
                  stroke="currentColor"
                  strokeLinejoin="round"
                  strokeWidth="1"
                  viewBox="-5.5 -6.5 12 12"
                >
                  <path d="M1.5 -5.3 A5.5 5.5 0 1 0 5.4 1.2 A4.4 4.4 0 0 1 1.5 -5.3 Z" />
                </svg>
                <span className="hidden sm:inline">Mac sleeps</span>
              </div>
            </div>
            <div className="relative h-5">
              <div className="absolute inset-x-0 top-1/2 h-px bg-border" />
              {MOMENTS.map((moment, index) => (
                <span
                  key={moment}
                  className={`absolute top-0 flex size-5 -translate-x-1/2 items-center justify-center rounded-full border bg-bg text-xs tabular-nums transition-colors duration-slow ${now >= moment ? "border-fg text-fg" : "border-border text-muted"}`}
                  style={{ left: `${moment * 100}%` }}
                >
                  {index + 1}
                </span>
              ))}
            </div>
            <div
              aria-hidden="true"
              className="pointer-events-none absolute -inset-y-1 w-px bg-fg"
              style={{ left: `${now * 100}%`, opacity: 0.3 * (1 - stretch(now, 0.96, 1, linear)) }}
            />
          </div>
        </div>
        <ol className="flex flex-col gap-2 pl-11 text-sm sm:grid sm:grid-cols-3 sm:gap-4 sm:pl-12 sm:text-center">
          {CAPTIONS.map((caption, index) => (
            <li
              key={caption}
              className={`flex gap-2 text-balance transition-colors duration-slow sm:block ${now >= MOMENTS[index] ? "text-fg" : "text-muted"}`}
            >
              <span className="tabular-nums text-muted sm:hidden">{index + 1}</span>
              {caption}
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
