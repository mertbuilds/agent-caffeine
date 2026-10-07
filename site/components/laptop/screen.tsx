import type { CSSProperties, ReactNode } from "react";
import { AgentIcon } from "@/components/agent-icons";

export const CLAUDE = "#D97757";
const GREEN = "#4eba65";
const TEXT = "#e5e5e5";
const DIM = "#8b8b8b";
const EDGE = "#5c5c5c";

const PROMPT = "refactor the auth module";
const TOOLS = ["Read", "Update", "Bash(bun test)"];
const SPINNER = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"];

/** The spinner glyph Claude Code shows `seconds` into its work. */
export function spinnerAt(seconds: number): string {
  return SPINNER[Math.floor(seconds / 0.12) % SPINNER.length];
}

/** Elapsed time the way Claude Code writes it: `48s`, `2m 14s`. */
function elapsed(seconds: number): string {
  const whole = Math.floor(seconds);
  const minutes = Math.floor(whole / 60);
  return minutes > 0 ? `${minutes}m ${whole % 60}s` : `${whole}s`;
}

type Session = {
  /** How much of the prompt is typed into the input box, from 0 to 1. */
  typed: number;
  /** How far the sent prompt has come into the transcript. */
  sent: number;
  /** How far each tool line has come in. A tool is done once the next one starts. */
  steps: readonly number[];
  /** Seconds the agent has worked, or null once it is done or before it starts. */
  working: number | null;
  spinner: string;
  done: boolean;
  /** The transcript's opacity, for clearing the screen before a replay. */
  shown: number;
};

/** One glyph in the room of one character, drawn as text where a font has it as an emoji too. */
function Cell({ children, color }: { children: string; color?: string }) {
  return (
    <span className="inline-block w-[1ch] text-center [font-variant-emoji:text]" style={{ color }}>
      {children}
    </span>
  );
}

function Line({ children, shown = 1, style }: { children: ReactNode; shown?: number; style?: CSSProperties }) {
  if (shown <= 0) {
    return null;
  }
  return (
    <div
      className="overflow-hidden whitespace-pre"
      style={{ opacity: shown, transform: `translateY(${(1 - shown) * 0.35}em)`, ...style }}
    >
      {children}
    </div>
  );
}

/** Claude Code in a terminal, cut down to what reads at a glance. */
export function Screen({ session }: { session: Session }) {
  const { typed, sent, steps, working, spinner, done, shown } = session;

  // On a small display the type is larger against the screen and the lines closer, so it still reads.
  return (
    <div
      aria-hidden="true"
      className="flex h-full flex-col gap-[0.7em] overflow-hidden bg-[#0d0d0d] px-[1.5ch] pt-[1.5em] text-left font-mono text-[calc(100cqw/30)] leading-[1.4] [font-variant-ligatures:none] [@container(max-width:299.98px)]:gap-[0.4em] [@container(max-width:299.98px)]:pt-[1.2em] [@container(max-width:299.98px)]:text-[calc(100cqw/25)]"
      style={{ color: TEXT }}
    >
      <div className="flex items-center gap-[1ch] whitespace-pre">
        <AgentIcon className="size-[1.4em] shrink-0" name="claudecode" />
        Claude Code
      </div>
      <div className="flex flex-col gap-[inherit]" style={{ opacity: shown }}>
        <Line shown={sent} style={{ backgroundColor: "#262626", marginInline: "-1.5ch", paddingInline: "1.5ch" }}>
          <span style={{ color: DIM }}>&gt;</span> {PROMPT}
        </Line>
        {TOOLS.map((tool, place) => (
          <Line key={tool} shown={steps[place]}>
            <Cell color={(place + 1 < TOOLS.length ? steps[place + 1] > 0 : done) ? GREEN : DIM}>⏺</Cell> {tool}
          </Line>
        ))}
        {done ? (
          <Line>
            <Cell>⏺</Cell> Done. All tests pass
          </Line>
        ) : null}
        {working === null ? null : (
          <Line>
            <span style={{ color: CLAUDE }}>
              <Cell>{spinner}</Cell> Refactoring…
            </span>{" "}
            <span style={{ color: DIM }}>({elapsed(working)})</span>
          </Line>
        )}
      </div>
      <div className="whitespace-pre rounded-[0.4em] border px-[1ch] py-[0.45em]" style={{ borderColor: EDGE }}>
        <span style={{ color: DIM }}>&gt;</span> {sent > 0 ? null : PROMPT.slice(0, Math.round(typed * PROMPT.length))}
        <span className="inline-block h-[1.2em] w-[1ch] align-[-0.2em]" style={{ backgroundColor: TEXT }} />
      </div>
    </div>
  );
}
