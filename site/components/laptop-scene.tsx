"use client";

import { easeInOut } from "motion/react";
import { useRef, useState } from "react";
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
const AT_CLOSE = 140;
const AT_DONE = 842;

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
  const seconds = AT_CLOSE * span(laptop.work, linear) + (AT_DONE - AT_CLOSE) * span(laptop.race, easeInOut);
  const spinner = spinnerAt(time);

  return (
    <div
      ref={ref}
      role="img"
      aria-label="A laptop runs Claude Code on a refactor. The lid closes and Claude Code keeps working for 14 minutes. The lid opens on the finished work, with all tests passing"
      className="relative aspect-[10/7] w-full [container-type:inline-size]"
    >
      <div className="absolute inset-0" style={{ perspective: "720cqw", perspectiveOrigin: "50% 30%" }}>
        <Laptop closed={closed} display={1 - stretch(closed, 0.2, 0.45, linear)}>
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
        <Pill shown={span(laptop.pillIn) - span(laptop.pillOut)} spinner={spinner} seconds={seconds} />
      </div>
    </div>
  );
}
