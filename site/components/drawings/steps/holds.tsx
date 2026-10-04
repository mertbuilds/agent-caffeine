"use client";

import { easeInOut } from "motion/react";
import { drawing } from "@/lib/motion";
import { Laptop, MenuBar, Panel, SCREEN, WorkLines } from "../parts";
import { LIFT } from "../scene";
import { LAPTOP_BOX, type StepProps, useStep } from "./use-step";

/** The hero's opening, quickened: two lines on the open laptop, the cup fills, the lid closes and the display lifts off. */
const LIVE = [0.1, 0.4] as const;
const LINES = [
  [0.2, 0.65],
  [0.75, 1.2],
] as const;
const CUP = [0.5, 1.3] as const;
const CLOSE = [1.4, 2.2] as const;
const HANDOFF = [1.4, 1.65] as const;
const LIFTED = [1.5, 2.3] as const;
/** With the lid shut, the work goes on in the panel. */
const MORE_LINES = [
  [2.35, 2.8],
  [2.9, 3.35],
] as const;

/**
 * The laptop open with an agent at work and the menu bar cup filling, then
 * the lid closing while the work goes on in a panel over it.
 */
export function HoldsDrawing({ play, ref }: StepProps) {
  const { lines, span } = useStep(play, drawing.stepHolds);
  const handoff = span(HANDOFF);
  const lift = span(LIFTED);
  const screen = (
    <>
      <MenuBar cup={span(CUP)} />
      <WorkLines live={span(LIVE)} shown={lines(LINES) + lines(MORE_LINES)} />
    </>
  );

  return (
    <svg
      ref={ref}
      aria-label="An agent works on a laptop. The cup in the menu bar fills, the lid closes and the agent keeps working"
      className="block aspect-[4/3] h-auto w-full"
      role="img"
      viewBox={LAPTOP_BOX}
    >
      <Laptop closed={span(CLOSE, easeInOut)}>
        <g opacity={1 - handoff}>{screen}</g>
      </Laptop>
      <Panel outline={lift} shown={handoff} y={SCREEN.y - LIFT * lift}>
        {screen}
      </Panel>
    </svg>
  );
}
