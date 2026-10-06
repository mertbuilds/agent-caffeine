"use client";

import { easeInOut } from "motion/react";
import { useRef, useState } from "react";
import { lidBrightness, lidDegrees } from "@/components/laptop/geometry";
import { Laptop } from "@/components/laptop/laptop";
import { Pill } from "@/components/laptop/pill";
import { spinnerAt, Terminal } from "@/components/laptop/terminal";
import { laptop } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";

type Span = readonly [from: number, to: number];

const linear = (share: number) => share;

/** Seconds of work the timer shows when the lid shuts, and when the work is done. */
const AT_CLOSE = 45;
const AT_DONE = 842;

/** How many times a second the pill's timer steps, so each roll has time to read. */
const PILL_TICKS = 10;

export function LaptopScene() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useSeen(ref, 0.4);
  const hidden = useTabHidden();
  const at = useLoop(seen && !hidden, laptop.loop, laptop.rest);

  // The playhead winds back to the start before each replay. Played backwards
  // the story makes no sense, so the finished screen clears instead.
  const [last, setLast] = useState(at);
  const [winding, setWinding] = useState(false);
  if (at !== last) {
    setLast(at);
    setWinding(at < last);
  }

  const time = winding ? laptop.loop : at * laptop.loop;
  const span = ([from, to]: Span, ease?: (share: number) => number) =>
    stretch(time, from, to, ease);

  const closed = span(laptop.close, easeInOut) - span(laptop.open, easeInOut);
  const done = time >= laptop.race[0];
  const workedAt = (at: number) =>
    AT_CLOSE * stretch(at, ...laptop.work, linear) +
    (AT_DONE - AT_CLOSE) * stretch(at, ...laptop.race, easeInOut);
  const seconds = workedAt(time);
  const spinner = spinnerAt(time);

  return (
    <div
      ref={ref}
      role="img"
      aria-label="A laptop runs Claude Code on a refactor. The lid closes one second after the prompt is sent, the display goes dark with it, and Claude Code keeps working for 14 minutes. The lid opens on the finished work, with all tests passing"
      className="relative aspect-[10/7] w-full [container-type:inline-size]"
    >
      <div className="absolute inset-0" style={{ perspective: "200cqw", perspectiveOrigin: "50% 22%" }}>
        <Laptop closed={closed} display={lidBrightness(lidDegrees(closed))}>
          <Terminal
            session={{
              welcome: span(laptop.welcome),
              typed: span(laptop.type, linear),
              sent: span(laptop.sent),
              steps: laptop.steps.map((step) => span(step)),
              working: time >= laptop.sent[0] && !done ? seconds : null,
              spinner,
              done,
              shown: winding ? at : 1,
            }}
          />
        </Laptop>
        <Pill
          shown={span(laptop.pillIn) - span(laptop.pillOut)}
          spinner={spinner}
          seconds={Math.floor(workedAt(Math.floor(time * PILL_TICKS) / PILL_TICKS))}
        />
      </div>
    </div>
  );
}
