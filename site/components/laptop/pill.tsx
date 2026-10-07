import NumberFlow, { NumberFlowGroup } from "@number-flow/react";
import { MenuIcon } from "@/components/menu-icon";
import { Working } from "./screen";

const TWO_DIGITS = { minimumIntegerDigits: 2 };
// A little longer than the timer's 100 ms step, so the rolls run into each other like fast counting.
const ROLL = { duration: 160, easing: "ease-out" };
const FADE = { duration: 80, easing: "ease-out" };

type PillProps = {
  /** How far the pill has come in, from 0 to 1. */
  shown: number;
  /** Seconds into the loop, which the dots of work under way keep time with. */
  at: number;
  /** Whole seconds of work, stepped a few times a second. */
  seconds: number;
};

/** The note above the closed laptop: the agent is still working. */
export function Pill({ shown, at, seconds }: PillProps) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="absolute left-1/2 bottom-[47%] flex items-center gap-[0.6em] whitespace-nowrap rounded-full border border-[var(--border)] bg-[var(--bg)] px-[1em] py-[0.55em] text-[clamp(11px,2.3cqw,16px)] leading-none text-fg"
      style={{
        opacity: shown,
        transform: `translate(-50%, ${(1 - shown) * 0.6}em) scale(${0.96 + shown * 0.04})`,
        boxShadow: "0 0.5em 1.5em var(--shadow)",
      }}
    >
      <Working seconds={at} />
      <span>Still working</span>
      <span aria-hidden="true" className="tabular-nums text-muted">
        <NumberFlowGroup>
          <span className="inline-block w-[2ch] text-right">
            <NumberFlow
              value={Math.floor(seconds / 60)}
              transformTiming={ROLL}
              spinTiming={ROLL}
              opacityTiming={FADE}
            />
          </span>
          m{" "}
          <NumberFlow
            value={seconds % 60}
            format={TWO_DIGITS}
            transformTiming={ROLL}
            spinTiming={ROLL}
            opacityTiming={FADE}
          />
          s
        </NumberFlowGroup>
      </span>
      <MenuIcon className="h-[1.1em] w-[1.1em] shrink-0 text-[var(--accent)]" held />
    </div>
  );
}
