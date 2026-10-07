import type { CSSProperties, ReactNode } from "react";

const TEXT = "#e5e5e5";
const DIM = "#8b8b8b";
const EDGE = "#5c5c5c";

const PROMPT = "refactor the auth module";
const STEPS = ["Read the code", "Edit 6 files", "Run the tests"];

/** Seconds the light takes to run over the three dots of work under way. */
const BEAT = 0.9;

function count(amount: number, unit: string): string {
  return `${amount} ${unit}${amount === 1 ? "" : "s"}`;
}

/** Elapsed time in full words: `48 seconds`, `2 minutes 14 seconds`. */
function elapsed(seconds: number): string {
  const whole = Math.floor(seconds);
  const minutes = Math.floor(whole / 60);
  return minutes > 0 ? `${count(minutes, "minute")} ${count(whole % 60, "second")}` : count(whole, "second");
}

type Session = {
  /** How much of the prompt is typed into the input, from 0 to 1. */
  typed: number;
  /** How far the sent prompt has turned into the task's title, and its steps have come in. */
  sent: number;
  /** How far each step's check has come in. A step works once the one before it is checked. */
  steps: readonly number[];
  /** Seconds the agent has worked, or null once it is done or before it starts. */
  working: number | null;
  /** Seconds into the loop, which the dots of work under way keep time with. */
  seconds: number;
  done: boolean;
  /** The task's opacity, for clearing the screen before a replay. */
  shown: number;
};

/** The mark of work under way: three dots, lit one after the other. */
export function Working({ seconds }: { seconds: number }) {
  const lit = ((seconds / BEAT) % 1) * 3;
  return (
    <span className="inline-flex w-[1em] shrink-0 items-center justify-between text-[var(--accent)]">
      {[0, 1, 2].map((dot) => {
        const away = Math.abs(((lit - dot + 4.5) % 3) - 1.5);
        return (
          <span
            key={dot}
            className="size-[0.26em] rounded-full bg-current"
            style={{ opacity: 0.4 + 0.6 * Math.max(0, 1 - away) }}
          />
        );
      })}
    </span>
  );
}

/** A step's mark: a quiet dot while it waits, the dots of work under way, then a check. */
function Mark({ working, done, seconds }: { working: number; done: number; seconds: number }) {
  return (
    <span className="relative inline-flex size-[1em] shrink-0 items-center justify-center">
      <span className="absolute size-[0.26em] rounded-full" style={{ backgroundColor: DIM, opacity: 1 - working }} />
      {working > 0 && done < 1 ? (
        <span className="absolute inset-0 flex items-center" style={{ opacity: working * (1 - done) }}>
          <Working seconds={seconds} />
        </span>
      ) : null}
      <svg
        viewBox="0 0 16 16"
        className="absolute inset-0 size-full text-[var(--accent)]"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={1.5}
        style={{ opacity: done }}
      >
        <path d="M3.5 8.5l3 3 6-7" />
      </svg>
    </span>
  );
}

function Line({ children, shown = 1, style }: { children: ReactNode; shown?: number; style?: CSSProperties }) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="flex items-center gap-[0.6em] overflow-hidden whitespace-pre"
      style={{ opacity: shown, transform: `translateY(${(1 - shown) * 0.35}em)`, ...style }}
    >
      {children}
    </div>
  );
}

export function Screen({ session }: { session: Session }) {
  const { typed, sent, steps, working, seconds, done, shown } = session;
  // The input stands empty again while the finished task clears.
  const input = 1 - sent * shown;

  return (
    <div
      aria-hidden="true"
      className="h-full bg-[#0d0d0d] px-[9cqw] pt-[8.5cqw] text-left text-[5.2cqw] leading-[1.3]"
      style={{ color: TEXT }}
    >
      <div
        className="-mx-[0.7em] flex items-center whitespace-pre rounded-[0.5em] border px-[0.7em] py-[0.45em]"
        style={{ borderColor: `color-mix(in srgb, ${EDGE} ${input * 100}%, transparent)` }}
      >
        <span style={{ opacity: shown }}>{sent > 0 ? PROMPT : PROMPT.slice(0, Math.round(typed * PROMPT.length))}</span>
        <span className="h-[1.1em] w-[0.08em]" style={{ backgroundColor: TEXT, opacity: sent > 0 ? 1 - shown : 1 }} />
      </div>
      <div className="mt-[0.5em] flex flex-col gap-[0.5em]" style={{ opacity: shown }}>
        {STEPS.map((step, place) => {
          const started = place === 0 ? sent : steps[place - 1];
          // Only the step in hand is bright.
          const bright = started * (1 - steps[place]);
          return (
            <Line key={step} shown={sent} style={{ color: `color-mix(in srgb, ${TEXT} ${bright * 100}%, ${DIM})` }}>
              <Mark working={started} done={steps[place]} seconds={seconds} />
              {step}
            </Line>
          );
        })}
        {done ? (
          <Line style={{ marginTop: "0.5em" }}>
            <Mark working={1} done={1} seconds={seconds} />
            Done
          </Line>
        ) : null}
        {working === null ? null : (
          <Line style={{ color: DIM, marginTop: "0.5em", fontSize: "0.8em" }}>
            <span className="tabular-nums">Working for {elapsed(working)}</span>
          </Line>
        )}
      </div>
    </div>
  );
}
