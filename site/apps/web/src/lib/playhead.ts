import { clamp, cubicBezier, easeInOut, useMotionValue, type MotionValue } from 'motion/react';
import { useLayoutEffect } from 'react';
import { drawing, easing } from './motion.ts';
import { useLessMotion } from './use-less-motion.ts';

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

type Span = readonly [from: number, to: number];

/** How often the playhead moves on outside the spans where something moves without a step, in milliseconds. */
const STEP = 50;

/**
 * How far a drawing has played, from 0 to 1, over and over while `play` is
 * on: it plays to 1 over `seconds`, stands there for `rest` seconds, winds
 * back to 0 and plays again. It goes back to the start when `play` turns off,
 * and stands at the end for a reader who asked for less motion. It is a value
 * to listen to, so a frame draws only what its listener changes.
 *
 * `moving` names the spans of the play, in seconds, where something moves
 * without a step. There, and on the way back, the playhead moves with every
 * frame. Elsewhere it moves on every `STEP`, off the frames: so the browser
 * draws a frame only when a step changed something, and motion that needs
 * no script, such as a turning arc, costs the page nothing. Without `moving`
 * the whole play moves with every frame.
 */
export function useLoop(
  play: boolean,
  seconds: number,
  rest: number,
  moving?: ReadonlyArray<Span>,
): MotionValue<number> {
  const reduced = useLessMotion();
  const clock = useMotionValue(1);

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
    const started = performance.now();
    let frame = 0;
    let timer = 0;
    const tick = () => {
      const time = ((performance.now() - started) / 1000) % turn;
      clock.set(
        time < seconds
          ? time / seconds
          : time < seconds + rest
            ? 1
            : 1 - easeInOut((time - seconds - rest) / drawing.back),
      );
      // The next span where something moves, if the play is not in one now.
      const ahead = moving?.find(([, to]) => time < to);
      const wait =
        moving === undefined || time >= seconds + rest
          ? 0
          : ((ahead?.[0] ?? seconds + rest) - time) * 1000;
      if (wait <= 0) {
        frame = requestAnimationFrame(tick);
      } else {
        timer = window.setTimeout(tick, Math.min(STEP, wait));
      }
    };
    tick();
    return () => {
      cancelAnimationFrame(frame);
      window.clearTimeout(timer);
    };
  }, [clock, moving, play, reduced, rest, seconds]);

  return clock;
}
