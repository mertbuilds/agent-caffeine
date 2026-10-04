"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { detectedAgents } from "@/lib/agents";
import { duration, easing } from "@/lib/motion";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

const NAMES = detectedAgents.slice(0, -1);
const TICK = 1800;
const ROWS = [
  { dot: "bg-accent", sub: "CLI · active", time: "now" },
  { dot: "bg-accent", sub: "CLI · active", time: "now" },
  { dot: "bg-muted", sub: "Waiting for input", time: "2 minutes" },
] as const;
const SWAP = { duration: duration.fast, ease: easing.smoothOut };

const FIRST = { shown: [0, 1, 2], turn: 0 };

/** Each turn puts the next name into the next row, so the rows always hold three neighbours in the list. */
function next({ shown, turn }: typeof FIRST): typeof FIRST {
  return { shown: shown.map((name, row) => (row === turn % 3 ? turn + 3 : name)), turn: turn + 1 };
}

export function AgentsPanel() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.3);
  const hidden = useTabHidden();
  const lessMotion = useLessMotion();
  const [names, setNames] = useState(FIRST);
  const ticking = seen && !hidden && !lessMotion;

  useEffect(() => {
    if (!ticking) {
      return;
    }
    const timer = window.setInterval(() => setNames(next), TICK);
    return () => window.clearInterval(timer);
  }, [ticking]);

  return (
    <div
      ref={ref}
      aria-label="The Agent Caffeine menu bar panel, keeping the Mac awake while three agents run"
      className="w-full max-w-[26rem] rounded-lg border border-border bg-bg p-4 text-left text-sm shadow-[0_8px_24px_var(--shadow)]"
      role="img"
    >
      <div className="flex items-center justify-between gap-4">
        <span className="font-medium">Agent Caffeine</span>
        <span className="flex h-4 w-7 items-center justify-end rounded-full bg-accent p-0.5">
          <span className="size-3 rounded-full bg-white" />
        </span>
      </div>
      <p className="mt-1 text-muted">Keeping the Mac awake</p>
      <div className="my-3 h-px bg-border" />
      <ul className="flex flex-col gap-3">
        {ROWS.map((row, index) => {
          const name = NAMES[(lessMotion ? FIRST : names).shown[index] % NAMES.length];
          return (
            <li key={index} className="flex items-start gap-3">
              <span className="relative mt-[0.45rem] size-1.5 shrink-0">
                <span className={`absolute inset-0 rounded-full ${row.dot}`} />
                <AnimatePresence initial={false}>
                  <motion.span
                    key={name}
                    animate={{ opacity: 0, scale: 3 }}
                    className={`absolute inset-0 rounded-full ${row.dot}`}
                    exit={{ opacity: 0 }}
                    initial={{ opacity: 0.5, scale: 1 }}
                    transition={{ duration: duration.slow * 2, ease: easing.smoothOut }}
                  />
                </AnimatePresence>
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="grid">
                  <AnimatePresence initial={false}>
                    <motion.span
                      key={name}
                      animate={{ filter: "blur(0px)", opacity: 1, y: 0 }}
                      className="truncate [grid-area:1/1]"
                      exit={{ filter: "blur(2px)", opacity: 0, y: -8 }}
                      initial={{ filter: "blur(2px)", opacity: 0, y: 8 }}
                      transition={SWAP}
                    >
                      {name}
                    </motion.span>
                  </AnimatePresence>
                </span>
                <span className="text-muted">{row.sub}</span>
              </span>
              <span className="shrink-0 tabular-nums text-muted">{row.time}</span>
            </li>
          );
        })}
      </ul>
      <div className="my-3 h-px bg-border" />
      <div className="flex justify-between text-muted">
        <span>Preferences…</span>
        <span>Quit</span>
      </div>
    </div>
  );
}
