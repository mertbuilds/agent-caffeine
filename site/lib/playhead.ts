import {
  animate,
  clamp,
  cubicBezier,
  easeInOut,
  useMotionValue,
  useMotionValueEvent,
  type AnimationPlaybackControls,
} from "motion/react";
import { useLayoutEffect, useRef, useState } from "react";
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
 * How far a drawing has played, from 0 to 1, over `seconds`. It plays once
 * from the start each time `play` turns on, and winds back to the start when
 * it turns off. It stands at the end on the server and for a reader who asked
 * for less motion.
 */
export function usePlayhead(play: boolean, seconds: number): number {
  const reduced = useLessMotion();
  const clock = useMotionValue(1);
  const [at, setAt] = useState(1);
  const played = useRef(false);
  useMotionValueEvent(clock, "change", setAt);

  useLayoutEffect(() => {
    if (reduced) {
      clock.set(1);
      return;
    }
    if (play) {
      played.current = true;
      clock.set(0);
      const playing = animate(clock, 1, { duration: seconds, ease: "linear" });
      return () => playing.stop();
    }
    if (!played.current) {
      clock.set(0);
      return;
    }
    const back = animate(clock, 0, { duration: drawing.back, ease: easeInOut });
    return () => back.stop();
  }, [clock, play, reduced, seconds]);

  return reduced ? 1 : at;
}

/**
 * Like `usePlayhead`, but over and over while `play` is on: it plays to 1
 * over `seconds`, stands there for `rest` seconds, winds back to 0 and plays
 * again.
 */
export function useLoop(play: boolean, seconds: number, rest: number): number {
  const reduced = useLessMotion();
  const clock = useMotionValue(1);
  const [at, setAt] = useState(1);
  const played = useRef(false);
  useMotionValueEvent(clock, "change", setAt);

  useLayoutEffect(() => {
    if (reduced) {
      clock.set(1);
      return;
    }
    if (!play) {
      if (!played.current) {
        clock.set(0);
        return;
      }
      const back = animate(clock, 0, { duration: drawing.back, ease: easeInOut });
      return () => back.stop();
    }
    if (!played.current) {
      clock.set(0);
      played.current = true;
    }
    const turn = seconds + rest + drawing.back;
    const loop = () =>
      animate(clock, [0, 1, 1, 0], {
        duration: turn,
        ease: ["linear", "linear", easeInOut],
        repeat: Infinity,
        times: [0, seconds / turn, (seconds + rest) / turn, 1],
      });
    let stopped = false;
    let current: AnimationPlaybackControls =
      clock.get() > 0
        ? animate(clock, 0, {
            duration: drawing.back,
            ease: easeInOut,
            onComplete: () => {
              if (!stopped) current = loop();
            },
          })
        : loop();
    return () => {
      stopped = true;
      current.stop();
    };
  }, [clock, play, reduced, rest, seconds]);

  return reduced ? 1 : at;
}
