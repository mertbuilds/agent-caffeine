import {
  animate,
  clamp,
  cubicBezier,
  easeInOut,
  useMotionValue,
  useMotionValueEvent,
} from "motion/react";
import { useLayoutEffect, useState } from "react";
import { drawing, easing } from "@/lib/motion";
import { useLessMotion } from "@/lib/use-less-motion";

const smoothOut = cubicBezier(...easing.smoothOut);

/**
 * How far into the part of the play between `from` and `to` the playhead `at`
 * has got, eased smooth out unless told otherwise: nothing before it, all of
 * it after.
 */
export function stretch(
  at: number,
  from: number,
  to: number,
  ease: (share: number) => number = smoothOut,
): number {
  return ease(clamp(0, 1, (at - from) / (to - from)));
}

/**
 * How far a drawing has played, from 0 to 1, over and over while `play` is
 * on: it plays to 1 over `seconds`, stands there for `rest` seconds, winds
 * back to 0 and plays again. It goes back to the start when `play` turns off,
 * and stands at the end on the server and for a reader who asked for less
 * motion.
 */
export function useLoop(play: boolean, seconds: number, rest: number): number {
  const reduced = useLessMotion();
  const clock = useMotionValue(1);
  const [at, setAt] = useState(1);
  useMotionValueEvent(clock, "change", setAt);

  useLayoutEffect(() => {
    if (reduced) {
      clock.set(1);
      return;
    }
    if (!play) {
      clock.set(0);
      return;
    }
    const turn = seconds + rest + drawing.back;
    const current = animate(clock, [0, 1, 1, 0], {
      duration: turn,
      ease: ["linear", "linear", easeInOut],
      repeat: Infinity,
      times: [0, seconds / turn, (seconds + rest) / turn, 1],
    });
    return () => current.stop();
  }, [clock, play, reduced, rest, seconds]);

  return reduced ? 1 : at;
}
