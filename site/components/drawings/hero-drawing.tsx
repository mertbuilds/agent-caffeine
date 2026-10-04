"use client";

import { easeInOut } from "motion/react";
import { drawing } from "@/lib/motion";
import { Label, Laptop, MenuBar, Panel, SCREEN, WorkLines } from "./parts";
import { LIFT, OPENING, SCENE, useScene } from "./scene";

/** After the lid has closed, the work goes on: three more lines, then the check. */
const MORE_LINES = [
  [4.2, 4.8],
  [5.0, 5.6],
  [5.8, 6.4],
] as const;
const CUP = [0.4, 1.2] as const;
const LABEL = [3.6, 4.3] as const;
const DONE = [6.5, 7.0] as const;

export function HeroDrawing() {
  const { lines, ref, span } = useScene(drawing.hero);
  const shown = lines(OPENING.lines) + lines(MORE_LINES);
  const done = span(DONE);
  const lift = span(OPENING.lift);
  const handoff = span(OPENING.handoff);
  const screen = (
    <>
      <MenuBar cup={span(CUP)} />
      <WorkLines done={done} live={span(OPENING.live) * (1 - done)} shown={shown} />
    </>
  );

  return (
    <svg
      ref={ref}
      aria-label="A laptop runs an AI agent. The lid closes and the agent keeps working until the task is done"
      className="block aspect-[4/3] h-auto w-full"
      role="img"
      viewBox={SCENE}
    >
      <Laptop closed={span(OPENING.close, easeInOut)}>
        <g opacity={1 - handoff}>{screen}</g>
      </Laptop>
      <Panel outline={lift} shown={handoff} y={SCREEN.y - LIFT * lift}>
        {screen}
      </Panel>
      <Label color="var(--fg)" shown={span(LABEL)}>
        Lid closed, still working
      </Label>
    </svg>
  );
}
