"use client";

import { useEffect, useRef, useState, type CSSProperties } from "react";
import { AgentIcon } from "@/components/agent-icons";
import { SectionHeading } from "@/components/section-heading";
import { agents, agentsMoreThan, markedAgents } from "@/lib/agents";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

const UNMARKED = agents.filter((agent) => agent.icon === undefined);
/** How often the app checks the running processes, and so how often the wall is swept. */
const SWEEP = 5000;
/** How soon the first sweep comes once the wall is in view. */
const FIRST_SWEEP = 800;
/** How far behind its neighbour each tile is swept, in milliseconds. */
const STEP = 30;
/** Which marked agents run after each sweep, in turn. The first is also the still wall. */
const RUNNING = [
  [0, 1],
  [4, 9, 17],
  [2, 13],
  [6, 11, 22],
  [0, 19],
  [3, 8, 24],
  [1, 15, 20],
  [5, 12],
] as const;

function delay(index: number): CSSProperties {
  return { transitionDelay: `${index * STEP}ms`, animationDelay: `${index * STEP}ms` };
}

/** The soft light that passes over a tile as the wall is swept, played again on each new `sweep`. */
function Sweep({ index, sweep }: { index: number; sweep: number }) {
  if (sweep === 0) {
    return null;
  }
  return (
    <span
      key={sweep}
      aria-hidden="true"
      className="wall-sweep pointer-events-none absolute inset-0 rounded-[inherit]"
      style={delay(index)}
    />
  );
}

export function AgentsSection() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const lessMotion = useLessMotion();
  const [sweep, setSweep] = useState(0);
  const sweeping = seen && !hidden && !lessMotion;
  const running: readonly number[] = RUNNING[lessMotion ? 0 : sweep % RUNNING.length];

  useEffect(() => {
    if (!sweeping) {
      return;
    }
    const timer = window.setTimeout(() => setSweep((turn) => turn + 1), sweep === 0 ? FIRST_SWEEP : SWEEP);
    return () => window.clearTimeout(timer);
  }, [sweep, sweeping]);

  const shown = lessMotion ? 0 : sweep;

  return (
    <section className="mx-auto flex w-full max-w-[1120px] flex-col gap-12">
      <SectionHeading
        lead={`It checks the running processes every 5 seconds. More than ${agentsMoreThan} agents are on the list, and you can add your own`}
        title="It knows your agents"
      />
      <div ref={ref} className="flex flex-col gap-3">
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
          {markedAgents.map((agent, index) => {
            const on = running.includes(index);
            return (
              <li
                key={agent.name}
                className={`relative flex items-center gap-1.5 rounded-lg border px-2 py-2.5 text-sm transition-colors duration-slow ease-smooth-out ${on ? "border-fg" : "border-border"}`}
                style={delay(index)}
              >
                <Sweep index={index} sweep={shown} />
                <AgentIcon className="size-5 shrink-0" name={agent.icon} />
                <span className="truncate">{agent.name}</span>
                <span
                  aria-hidden="true"
                  className={`absolute -top-2 right-2 flex items-center gap-1 bg-bg px-1 text-xs leading-4 text-fg transition-[opacity,transform] duration-slow ease-smooth-out ${on ? "opacity-100" : "translate-y-0.5 opacity-0"}`}
                  style={delay(index)}
                >
                  <span className="size-1.5 rounded-full bg-accent" />
                  running
                </span>
              </li>
            );
          })}
        </ul>
        <ul className="flex flex-wrap gap-2 text-sm text-muted">
          {UNMARKED.map((agent, index) => (
            <li key={agent.name} className="relative rounded-lg border border-border px-3 py-1.5">
              <Sweep index={markedAgents.length + index} sweep={shown} />
              {agent.name}
            </li>
          ))}
          <li className="relative flex items-center gap-1.5 rounded-lg border border-dashed border-border px-3 py-1.5">
            <Sweep index={agents.length} sweep={shown} />
            <svg
              aria-hidden="true"
              className="size-3"
              fill="none"
              stroke="currentColor"
              strokeLinecap="round"
              strokeWidth="1.5"
              viewBox="0 0 12 12"
            >
              <path d="M6 1.5v9M1.5 6h9" />
            </svg>
            Your own
          </li>
        </ul>
      </div>
    </section>
  );
}
