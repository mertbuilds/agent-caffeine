import NumberFlow, { NumberFlowGroup } from "@number-flow/react";
import { AgentIcon } from "@/components/agent-icons";
import { MenuIcon } from "@/components/menu-icon";
import { CLAUDE } from "./screen";

// A little longer than the timer's 100 ms step, so the rolls run into each other like fast counting.
const ROLL = { duration: 160, easing: "ease-out" };
const FADE = { duration: 80, easing: "ease-out" };

const TIMING = { transformTiming: ROLL, spinTiming: ROLL, opacityTiming: FADE };

/** A number of up to two digits and its unit in full, in the room of two digits and the plural, so the pill keeps its width while the number races. */
function Count({ amount, unit }: { amount: number; unit: string }) {
  return (
    <>
      <span className="inline-block w-[2ch] text-right">
        <NumberFlow value={amount} locales="en-US" {...TIMING} />
      </span>{" "}
      <span className="inline-grid">
        <span className="invisible [grid-area:1/1]">{unit}s</span>
        <span className="[grid-area:1/1]">{amount === 1 ? unit : `${unit}s`}</span>
      </span>
    </>
  );
}

type PillProps = {
  /** How far the pill has come in, from 0 to 1. */
  shown: number;
  /** Claude Code's spinner glyph of the moment. */
  spinner: string;
  /** Whole seconds of work, stepped a few times a second. */
  seconds: number;
};

/** The note above the closed laptop: Claude Code is still working. */
export function Pill({ shown, spinner, seconds }: PillProps) {
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
      <AgentIcon className="size-[1.15em] shrink-0" name="claudecode" />
      <span className="inline-block w-[1ch] text-center font-mono [font-variant-emoji:text]" style={{ color: CLAUDE }}>
        {spinner}
      </span>
      <span>Still working</span>
      <span aria-hidden="true" className="tabular-nums text-muted">
        <NumberFlowGroup>
          <Count amount={Math.floor(seconds / 60)} unit="minute" /> <Count amount={seconds % 60} unit="second" />
        </NumberFlowGroup>
      </span>
      <MenuIcon className="h-[1.1em] w-[1.1em] shrink-0 text-[var(--accent)]" held />
    </div>
  );
}
