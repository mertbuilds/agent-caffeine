"use client";

import { useEffect, useRef, useState } from "react";
import { HoldsDrawing } from "@/components/drawings/steps/holds";
import { SeesDrawing } from "@/components/drawings/steps/sees";
import { SleepsDrawing } from "@/components/drawings/steps/sleeps";
import { drawing } from "@/lib/motion";
import { useLessMotion } from "@/lib/use-less-motion";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

const STEPS = [
  {
    title: "Sees your agents",
    body: "It checks the running processes every 5 seconds for Claude Code, Codex and 40 more",
    Drawing: SeesDrawing,
    seconds: drawing.stepSees,
  },
  {
    title: "Holds the Mac awake",
    body: "While an agent runs, the Mac stays awake, even with the lid closed",
    Drawing: HoldsDrawing,
    seconds: drawing.stepHolds,
  },
  {
    title: "Lets it sleep when done",
    body: "When the last agent stops, the Mac sleeps again and the battery is saved",
    Drawing: SleepsDrawing,
    seconds: drawing.stepSleeps,
  },
];

/** The turn in which every step goes back to its start, before the first plays again. */
const BACK = -1;

/**
 * The turn after `turn`, and how many seconds until it. A step on screen
 * plays to its end and one off screen gives up its turn at once. Once every
 * step on screen has played they rest, and then go back to their start.
 */
function following(
  turn: number,
  seen: readonly boolean[],
  seconds: readonly number[],
): { next: number; wait: number } {
  if (!seen.includes(true)) {
    return { next: 0, wait: 0 };
  }
  if (turn === BACK) {
    return { next: 0, wait: drawing.back };
  }
  if (seen.some((on, index) => on && index >= turn)) {
    return { next: turn + 1, wait: seen[turn] === true ? (seconds[turn] ?? 0) : 0 };
  }
  return { next: BACK, wait: drawing.stepRest };
}

/**
 * Which steps play: each while it is on screen, though not before the one
 * whose turn it is has played to its end, so steps on screen together play
 * one after another. Once all have played they stand finished for a rest, go
 * back to their start together and play again, for as long as one is on
 * screen.
 */
function useInTurn(seen: readonly boolean[], seconds: readonly number[]): readonly boolean[] {
  const [turn, setTurn] = useState(0);
  const { next, wait } = following(turn, seen, seconds);

  useEffect(() => {
    if (next === turn) {
      return;
    }
    const timer = setTimeout(() => setTurn(next), wait * 1000);
    return () => clearTimeout(timer);
  }, [next, turn, wait]);

  return seen.map((on, index) => on && index <= turn);
}

export function HowItWorks() {
  const sees = useRef<SVGSVGElement>(null);
  const holds = useRef<SVGSVGElement>(null);
  const sleeps = useRef<SVGSVGElement>(null);
  const refs = [sees, holds, sleeps];
  const seen = [useSeen(sees), useSeen(holds), useSeen(sleeps)];
  const hidden = useTabHidden();
  const reduced = useLessMotion();
  const playing = useInTurn(
    seen.map((on) => on && !hidden && !reduced),
    STEPS.map((step) => step.seconds),
  );

  return (
    <ol className="grid grid-cols-1 gap-12 sm:grid-cols-3 sm:gap-8">
      {STEPS.map(({ Drawing, ...step }, index) => (
        <li key={step.title} className="flex flex-col gap-3 text-center">
          <Drawing play={playing[index] === true} ref={refs[index]} />
          <h3 className="mt-2 text-balance font-medium leading-[1.4]">
            <span className="mr-1 font-normal tabular-nums text-muted">{index + 1}</span>{" "}
            {step.title}
          </h3>
          <p className="text-balance text-sm leading-normal text-muted">{step.body}</p>
        </li>
      ))}
    </ol>
  );
}
