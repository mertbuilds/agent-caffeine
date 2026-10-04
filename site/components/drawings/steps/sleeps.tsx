"use client";

import { easeInOut } from "motion/react";
import { drawing } from "@/lib/motion";
import {
  CLOSED_TOP,
  CUP_SIZE,
  Cup,
  Laptop,
  MENU_CUP,
  MenuBar,
  Panel,
  SCREEN,
  Sleep,
  WIDTH,
  WorkLines,
} from "../parts";
import { LIFT } from "../scene";
import { LAPTOP_BOX, type StepProps, useStep } from "./use-step";

/** As many lines as the step before ends with. */
const SHOWN = 4;
const DONE = [0.3, 0.8] as const;
const EMPTY = [0.9, 1.6] as const;
const FADE = [1.5, 2.2] as const;
const SLEEP = [2.0, 2.7] as const;
const PANEL_Y = SCREEN.y - LIFT;
/** Where `MenuBar` puts its cup, here kept out of the panel so it stays once the panel has gone. */
const CUP_FROM = { x: SCREEN.x + MENU_CUP.x, y: PANEL_Y + MENU_CUP.y };
/** Where the emptied cup is set down, on the middle of the closed lid. */
const CUP_TO = {
  x: WIDTH / 2 - (CUP_SIZE.width * MENU_CUP.scale) / 2,
  y: CLOSED_TOP - CUP_SIZE.saucer * MENU_CUP.scale,
};
/** Where the moon stands, over the cup. */
const MOON = { x: 117, y: 104 };

/**
 * From where the step before ends, the lid closed and the work going on in
 * the panel: the last line gets its check, the live dot goes out, the cup
 * empties, the panel fades as the cup comes down onto the lid, and the
 * laptop goes to sleep.
 */
export function SleepsDrawing({ play, ref }: StepProps) {
  const { span } = useStep(play, drawing.stepSleeps);
  const done = span(DONE);
  const fade = span(FADE);
  const down = span(FADE, easeInOut);
  const cupX = CUP_FROM.x + (CUP_TO.x - CUP_FROM.x) * down;
  const cupY = CUP_FROM.y + (CUP_TO.y - CUP_FROM.y) * down;

  return (
    <svg
      ref={ref}
      aria-label="The agent finishes. The cup in the menu bar empties and the closed laptop goes to sleep"
      className="block aspect-[4/3] h-auto w-full"
      role="img"
      viewBox={LAPTOP_BOX}
    >
      <Laptop closed={1} />
      <Panel outline={1} shown={1 - fade} y={PANEL_Y}>
        <MenuBar />
        <WorkLines done={done} live={1 - done} shown={SHOWN} />
      </Panel>
      <g transform={`translate(${cupX} ${cupY}) scale(${MENU_CUP.scale})`}>
        <Cup full={1 - span(EMPTY)} />
      </g>
      <g transform={`translate(${MOON.x} ${MOON.y})`}>
        <Sleep shown={span(SLEEP)} />
      </g>
    </svg>
  );
}
