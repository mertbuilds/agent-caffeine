"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { duration, easing } from "@/lib/motion";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

const TICK = 1800;
const SWAP = { duration: duration.fast, ease: easing.smoothOut };

/** Process names from the app's default allowlist, in the order the CLI rows take them. */
const PROCESSES = [
  "claude",
  "codex",
  "opencode",
  "pi",
  "gemini",
  "aider",
  "amp",
  "goose",
  "cursor-agent",
  "crush",
  "kiro-cli",
];

const SESSION = { label: "website · Fix flaky checkout test", sub: "Claude Code · Waiting for input" };

const FIRST = { shown: [0, 1], turn: 0 };

/** Each turn puts the next name into the next CLI row, so the two rows always hold neighbours in the list. */
function next({ shown, turn }: typeof FIRST): typeof FIRST {
  return { shown: shown.map((name, row) => (row === turn % 2 ? turn + 2 : name)), turn: turn + 1 };
}

const TERTIARY = "text-[color-mix(in_srgb,var(--muted)_70%,transparent)]";

function Row({ dot, label, sub, time }: { dot: string; label: ReactNode; sub: string; time: string }) {
  return (
    <li className="flex items-center gap-2">
      <span className="size-2 shrink-0 rounded-full" style={{ background: dot }} />
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="grid text-[12px] leading-[15px]">{label}</span>
        <span className="truncate text-[10px] leading-[13px] text-muted">{sub}</span>
      </span>
      <span className={`shrink-0 text-[10px] tabular-nums ${TERTIARY}`}>{time}</span>
    </li>
  );
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
      aria-label="The agent caffeine menu bar panel, set to keep the Mac awake while an agent is working. It keeps the Mac awake while two command line agents work and a Claude Code session waits for input"
      className="flex w-full flex-col gap-3 rounded-[10px] border border-border bg-bg p-3 text-left shadow-[0_8px_24px_var(--shadow)]"
      role="img"
    >
      <div aria-hidden="true" className="flex flex-col gap-1">
        <div className="flex items-center justify-between gap-4">
          <span className="text-[13px] font-medium leading-4">agent caffeine</span>
          <span className="flex h-4 w-[26px] items-center justify-end rounded-full bg-accent p-px">
            <span className="size-3.5 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.25)]" />
          </span>
        </div>
        <p className="text-[12px] leading-[15px] text-muted">Keeping the Mac awake</p>
        <span className="flex h-[18px] items-center gap-1.5 self-start rounded-[5px] border border-border bg-bg pl-2 pr-px text-[11px] leading-[13px] shadow-[0_1px_1px_var(--shadow)]">
          While an agent is working
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
        </span>
      </div>
      <div className="h-px bg-border" />
      <ul aria-hidden="true" className="flex flex-col gap-1">
        {(lessMotion ? FIRST : names).shown.map((index, row) => {
          const name = PROCESSES[index % PROCESSES.length];
          return (
            <Row
              key={row}
              dot="#34c759"
              label={
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
              }
              sub="CLI · Active"
              time="now"
            />
          );
        })}
        <Row
          dot="#ffcc00"
          label={<span className="truncate">{SESSION.label}</span>}
          sub={SESSION.sub}
          time="2m"
        />
      </ul>
      <div className="h-px bg-border" />
      <div aria-hidden="true" className="flex justify-between text-[12px] leading-[15px]">
        <span>Preferences…</span>
        <span>Quit</span>
      </div>
    </div>
  );
}
