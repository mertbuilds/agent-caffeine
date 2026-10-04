"use client";

import { easeInOut } from "motion/react";
import { drawing } from "@/lib/motion";
import { Label, Laptop, MenuBar, Panel, SCREEN, Sleep, WorkLines } from "./parts";
import { LIFT, OPENING, SCENE, useScene } from "./scene";

/** As the lid closes the live dot goes out, then the lines fade to this. */
const DOT_OUT = [2.7, 3.2] as const;
const FADE = [2.9, 3.9] as const;
const FADED = 0.35;
const SLEEP = [3.8, 4.5] as const;
const LABEL = [4.2, 4.9] as const;
/** Where the moon stands, over the closed laptop, right of the panel. */
const MOON = { x: 186, y: 117 };

export function WithoutDrawing() {
  const { lines, ref, span } = useScene(drawing.without);
  const lift = span(OPENING.lift);
  const handoff = span(OPENING.handoff);
  const screen = (
    <>
      <MenuBar />
      <WorkLines live={span(OPENING.live) * (1 - span(DOT_OUT))} shown={lines(OPENING.lines)} />
    </>
  );

  return (
    <svg
      ref={ref}
      aria-label="Without Agent Caffeine, the lid closes, the Mac goes to sleep and the agent loses its connection"
      className="block aspect-[4/3] h-auto w-full"
      role="img"
      viewBox={SCENE}
    >
      <Laptop closed={span(OPENING.close, easeInOut)}>
        <g opacity={1 - handoff}>{screen}</g>
      </Laptop>
      <Panel outline={lift} shown={handoff} y={SCREEN.y - LIFT * lift}>
        <g opacity={1 - (1 - FADED) * span(FADE)}>{screen}</g>
      </Panel>
      <g transform={`translate(${MOON.x} ${MOON.y})`}>
        <Sleep shown={span(SLEEP)} />
      </g>
      <Label color="var(--error)" shown={span(LABEL)}>
        Connection lost
      </Label>
    </svg>
  );
}
